//
//  PurchaseService.swift
//  DogHouse
//
//  Real-money treat packs, sold as App Store consumables through RevenueCat.
//
//  Like every other economy action, the phone does not move the currency: it
//  runs the StoreKit purchase and stops there. RevenueCat verifies the receipt
//  with Apple and calls the `revenuecatWebhook` Cloud Function, which credits
//  `users/{uid}.treats` with admin privileges. The balance then arrives the
//  same way a cosmetic purchase does — through the user-document listener that
//  AuthService already runs.
//
//  ── Keys ──
//  `purchases-ios` is linked into the app target. Everything that touches it
//  stays behind `#if canImport(RevenueCat)` so the widget and test targets,
//  which do not link it, still compile this file's model types.
//
//  Two public SDK keys, chosen at compile time:
//    Debug   → RevenueCat *Test Store* key (`test_…`): fake purchases on the
//              simulator with a success / fail / cancel modal, no App Store
//              Connect products needed. Its webhooks arrive as SANDBOX.
//    Release → App Store key (`appl_…`): TestFlight sandbox and real money.
//  A Release build refuses a `test_` key outright (see `configure`), so a
//  test key can never reach an archive. Until a real key is pasted the
//  placeholder keeps `isAvailable` false and the Shop hides the store.
//  See the README's RevenueCat section.
//

import Foundation
import Combine
import FirebaseAuth
import OSLog

#if canImport(RevenueCat)
import RevenueCat
#endif

// MARK: - Model

/// One purchasable pack. Deliberately free of RevenueCat types so the Shop UI
/// compiles whether or not the SDK is present.
struct TreatPack: Identifiable, Hashable {
    let id: String          // App Store product id
    let treats: Int         // Mirrors TREAT_PRODUCTS in functions/src/index.ts
    let displayPrice: String // Localized, straight from the store

    /// Treat amounts are decided server-side; this table only labels the
    /// buttons. It must stay in sync with `TREAT_PRODUCTS` in
    /// `functions/src/index.ts`, which is the authority — if they ever
    /// disagree the server wins and the user gets what the server says.
    static let treatsByProductId: [String: Int] = [
        "com.Harrison.DogHouse.treats.small": 250,
        "com.Harrison.DogHouse.treats.medium": 900,
        "com.Harrison.DogHouse.treats.large": 1600,
    ]

    /// Nice-to-have label for the biggest pack.
    var isBestValue: Bool { id == "com.Harrison.DogHouse.treats.large" }
    var isMostPopular: Bool { id == "com.Harrison.DogHouse.treats.medium" }

    /// Store-front dressing. Purely cosmetic: the amount and the price are
    /// the authorities, this only makes the three tiers feel distinct.
    var tierName: String {
        switch id {
        case "com.Harrison.DogHouse.treats.small":  "Handful"
        case "com.Harrison.DogHouse.treats.medium": "Pouch"
        default:                                    "Sack"
        }
    }

    /// How many bones to draw on the tier badge.
    var tierBones: Int {
        switch id {
        case "com.Harrison.DogHouse.treats.small":  1
        case "com.Harrison.DogHouse.treats.medium": 2
        default:                                    3
        }
    }

    /// Treats-per-money advantage over the smallest pack, at the list prices
    /// in the RevenueCat dashboard ($0.99 / $2.99 / $4.99). Worded without a
    /// currency symbol because the price itself is localized by the store.
    /// Nil for the base tier.
    var bonusLabel: String? {
        switch id {
        case "com.Harrison.DogHouse.treats.medium": "19% better value"
        case "com.Harrison.DogHouse.treats.large":  "27% better value"
        default:                                    nil
        }
    }

    #if DEBUG
    /// Fake line-up for `-demoOnboarding` runs, where there is no store to
    /// ask. Prices mirror the planned App Store list prices.
    static let demoPacks: [TreatPack] = [
        TreatPack(id: "com.Harrison.DogHouse.treats.small",  treats: 250,  displayPrice: "$0.99"),
        TreatPack(id: "com.Harrison.DogHouse.treats.medium", treats: 900,  displayPrice: "$2.99"),
        TreatPack(id: "com.Harrison.DogHouse.treats.large",  treats: 1600, displayPrice: "$4.99"),
    ]
    #endif
}

/// One DogHouse Premium plan (the `premium` offering). Like `TreatPack`, free
/// of RevenueCat types so the paywall compiles without the SDK.
struct PremiumPlan: Identifiable, Hashable {
    let id: String              // App Store product id
    let title: String           // "6 months" / "Yearly"
    let displayPrice: String    // Localized, straight from the store
    /// "per 6 months" / "per year".
    let periodLabel: String
    /// "7 days free", when the store offers a free trial on this product.
    let trialLabel: String?
    /// e.g. "$2.08/month", for comparing plans at a glance.
    let perMonthLabel: String?

    var isYearly: Bool { id == PremiumPlan.yearlyId }

    static let sixMonthId = "premium_six_month"
    static let yearlyId = "premium_yearly"
    /// RevenueCat entitlement both plans unlock.
    static let entitlementId = "DogHouse+"
    /// RevenueCat offering holding the two plans. The Treat Store keeps
    /// reading `offerings.current`.
    static let offeringId = "premium"

    #if DEBUG
    /// Fake plans for `-demoOnboarding` runs, at the Test Store prices.
    static let demoPlans: [PremiumPlan] = [
        PremiumPlan(id: sixMonthId, title: "6 months", displayPrice: "$17.99",
                    periodLabel: "per 6 months", trialLabel: nil, perMonthLabel: "$3.00/month"),
        PremiumPlan(id: yearlyId, title: "Yearly", displayPrice: "$24.99",
                    periodLabel: "per year", trialLabel: "7 days free", perMonthLabel: "$2.08/month"),
    ]
    #endif
}

// MARK: - Service

@MainActor
final class PurchaseService: ObservableObject {
    static let shared = PurchaseService()

    /// RevenueCat's *public* SDK key. Publishable — it is designed to ship
    /// inside the app binary. Never put a secret key here.
    ///
    /// Debug builds use the Test Store key (`test_…`), Release builds the App
    /// Store key (`appl_…`). Paste each one in place of its placeholder.
    #if DEBUG
    private static let publicSDKKey = "test_REPLACE_ME"
    private static let isDebugBuild = true
    #else
    private static let publicSDKKey = "appl_REPLACE_ME"
    private static let isDebugBuild = false
    #endif

    /// Whether `key` may configure the SDK in this kind of build.
    ///
    /// Placeholders and empty strings never do. A Test Store key (`test_`) is
    /// only usable in Debug: it would make a shipping app sell fake treats.
    /// The App Store key (`appl_`) is usable everywhere, so a Debug build can
    /// also be pointed at the real sandbox when needed.
    nonisolated static func isUsableKey(_ key: String, debug: Bool) -> Bool {
        guard !key.isEmpty, !key.hasSuffix("REPLACE_ME") else { return false }
        if key.hasPrefix("appl_") { return true }
        if key.hasPrefix("test_") { return debug }
        return false
    }

    @Published private(set) var packs: [TreatPack] = []
    @Published private(set) var isLoading = false
    @Published private(set) var purchasingProductId: String?

    private let log = Logger(subsystem: Logger.subsystem, category: "purchases")

    // Premium
    @Published private(set) var premiumPlans: [PremiumPlan] = []
    @Published private(set) var isLoadingPremium = false
    @Published private(set) var subscribingPlanId: String?
    @Published private(set) var isRestoring = false
    /// This device's RevenueCat view of the `DogHouse+` entitlement. Optimistic:
    /// it flips the moment the purchaser pays, before the webhook has written
    /// `premiumUntil`. The server stays the authority for the game limit.
    @Published private(set) var hasPremiumEntitlement = false

    #if canImport(RevenueCat)
    /// Product id → the RevenueCat package to buy, kept out of `TreatPack`.
    private var packagesByProductId: [String: Package] = [:]
    private var premiumPackagesById: [String: Package] = [:]
    #endif

    private init() {
        #if DEBUG
        hasPremiumEntitlement = Self.demoStartsPremium
        #endif
    }

    /// Whether treat packs can be offered at all. False until a key that is
    /// valid for this kind of build is set, which is what keeps the Shop from
    /// showing a buy button that cannot work.
    var isAvailable: Bool {
        #if DEBUG
        if AuthService.isDemo { return true }
        #endif
        #if canImport(RevenueCat)
        return Self.isUsableKey(Self.publicSDKKey, debug: Self.isDebugBuild)
        #else
        return false
        #endif
    }

    #if DEBUG
    /// Demo runs never touch StoreKit: `buy` pretends to pay and the Shop
    /// credits the balance locally through `AuthService.demoAddTreats`.
    var isDemo: Bool { AuthService.isDemo }

    /// `-demoPremium`: the demo couple starts subscribed. Without it the demo
    /// starts free, so the daily limit and the paywall can be recorded.
    static let demoStartsPremium = AuthService.isDemo
        && ProcessInfo.processInfo.arguments.contains("-demoPremium")

    /// Premium as the demo's local game limit sees it.
    var demoCouplePremium: Bool { hasPremiumEntitlement }
    #endif

    /// Whether the couple is premium: my own `premiumUntil`, my partner's,
    /// or this device's entitlement (optimistic, until the webhook lands).
    /// One subscription covers both, so unpairing drops it for the non-payer.
    func isCouplePremium(me: UserProfile?, partner: UserProfile?) -> Bool {
        hasPremiumEntitlement
            || (me?.isPremiumActive ?? false)
            || (partner?.isPremiumActive ?? false)
    }

    // MARK: - Lifecycle

    /// Call once at launch, after `FirebaseApp.configure()`.
    func configure() {
        #if DEBUG
        if isDemo { return }
        #endif
        #if canImport(RevenueCat)
        guard isAvailable else {
            if Self.publicSDKKey.hasPrefix("test_") && !Self.isDebugBuild {
                // Disable rather than crash: a shipping app must never sell
                // fake treats, but it must not die at launch either.
                log.fault("Test Store key in a release build — treat packs disabled")
            } else {
                log.notice("RevenueCat SDK key not set — treat packs disabled")
            }
            return
        }
        let store = Self.publicSDKKey.hasPrefix("test_") ? "Test Store" : "App Store"
        log.notice("Configuring RevenueCat against the \(store, privacy: .public)")
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: Self.publicSDKKey)
        // Keep the premium entitlement current (purchase, renewal, expiry,
        // restore on another device) without polling.
        Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.applyCustomerInfo(info)
            }
        }
        #endif
    }

    /// Tie RevenueCat's app_user_id to the Firebase uid, so the webhook's
    /// `app_user_id` is the same string as the `users/{uid}` document id.
    /// Without this the purchase arrives under an anonymous id and the
    /// webhook has no user to credit.
    func login(uid: String) async {
        #if DEBUG
        if isDemo { return }
        #endif
        #if canImport(RevenueCat)
        guard isAvailable else { return }
        do {
            let (info, _) = try await Purchases.shared.logIn(uid)
            applyCustomerInfo(info)
        } catch {
            log.error("RevenueCat logIn failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    /// Guarantee RevenueCat knows who is buying, immediately before anything
    /// that depends on it.
    ///
    /// `login(uid:)` is fired from the auth-state listener and does not block
    /// the UI, so a fast user could otherwise reach the Shop and pay while the
    /// identity is still anonymous. A purchase made under a `$RCAnonymousID`
    /// has no `users/{uid}` document for the webhook to credit — the money is
    /// taken and the treats never arrive. Re-asserting it here is idempotent.
    private func ensureIdentified() async {
        #if DEBUG
        if isDemo { return }
        #endif
        #if canImport(RevenueCat)
        guard isAvailable, let uid = Auth.auth().currentUser?.uid else { return }
        guard Purchases.shared.appUserID != uid else { return }
        await login(uid: uid)
        #endif
    }

    /// Detach the account on sign-out so the next user on this device does not
    /// inherit the previous one's purchase identity.
    func logOut() async {
        #if DEBUG
        if isDemo { return }
        #endif
        #if canImport(RevenueCat)
        guard isAvailable else { return }
        _ = try? await Purchases.shared.logOut()
        packs = []
        packagesByProductId = [:]
        premiumPlans = []
        premiumPackagesById = [:]
        hasPremiumEntitlement = false
        #endif
    }

    // MARK: - Offerings

    /// Load the current pack lineup. Prices come from the store, never from a
    /// hard-coded table, so App Store Connect stays the source of truth for money.
    func loadPacks() async {
        #if DEBUG
        if isDemo {
            packs = TreatPack.demoPacks
            return
        }
        #endif
        #if canImport(RevenueCat)
        guard isAvailable, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        await ensureIdentified()

        do {
            let offerings = try await Purchases.shared.offerings()
            let available = offerings.current?.availablePackages ?? []

            var loaded: [TreatPack] = []
            var index: [String: Package] = [:]

            for package in available {
                let productId = package.storeProduct.productIdentifier
                // Only surface packs the server actually knows how to credit.
                guard let treats = TreatPack.treatsByProductId[productId] else {
                    log.notice("Skipping unmapped product \(productId, privacy: .public)")
                    continue
                }
                loaded.append(TreatPack(
                    id: productId,
                    treats: treats,
                    displayPrice: package.storeProduct.localizedPriceString
                ))
                index[productId] = package
            }

            packs = loaded.sorted { $0.treats < $1.treats }
            packagesByProductId = index
        } catch {
            log.error("Loading offerings failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    // MARK: - Purchase

    /// Run the store purchase. Returns true when the user actually paid.
    ///
    /// This never writes `treats` — security rules would reject it anyway. The
    /// caller shows a pending state and waits for the listener to catch up;
    /// that waiting state belongs to the presenting sheet, not to this
    /// service, so a dismissed sheet never leaves a stale "Adding…" behind.
    @discardableResult
    func buy(_ pack: TreatPack) async throws -> Bool {
        #if DEBUG
        if isDemo {
            purchasingProductId = pack.id
            defer { purchasingProductId = nil }
            try? await Task.sleep(for: .seconds(0.9))
            return true
        }
        #endif
        #if canImport(RevenueCat)
        guard let package = packagesByProductId[pack.id] else { return false }

        purchasingProductId = pack.id
        defer { purchasingProductId = nil }

        // Never let money move under an anonymous identity.
        await ensureIdentified()

        let result = try await Purchases.shared.purchase(package: package)
        guard !result.userCancelled else { return false }

        // Paid. The webhook credits the treats; the balance will arrive on the
        // user-document listener within a few seconds.
        return true
        #else
        return false
        #endif
    }

    // MARK: - Premium (couple-shared subscription)

    /// Load the two premium plans from the `premium` offering. The Treat
    /// Store's `loadPacks` keeps reading `offerings.current`.
    func loadPremium() async {
        #if DEBUG
        if isDemo {
            premiumPlans = PremiumPlan.demoPlans
            return
        }
        #endif
        #if canImport(RevenueCat)
        guard isAvailable, !isLoadingPremium else { return }
        isLoadingPremium = true
        defer { isLoadingPremium = false }

        await ensureIdentified()

        do {
            let offerings = try await Purchases.shared.offerings()
            let available = offerings.offering(identifier: PremiumPlan.offeringId)?.availablePackages ?? []

            var loaded: [PremiumPlan] = []
            var index: [String: Package] = [:]
            for package in available {
                let product = package.storeProduct
                let id = product.productIdentifier
                guard id == PremiumPlan.sixMonthId || id == PremiumPlan.yearlyId else {
                    log.notice("Skipping unexpected premium product \(id, privacy: .public)")
                    continue
                }
                // Only advertise a trial the store would actually give.
                var trialLabel: String?
                if let intro = product.introductoryDiscount, intro.paymentMode == .freeTrial {
                    let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(product: product)
                    if eligibility != .ineligible {
                        trialLabel = Self.trialLabel(intro.subscriptionPeriod)
                    }
                }
                let isYearly = id == PremiumPlan.yearlyId
                loaded.append(PremiumPlan(
                    id: id,
                    title: isYearly ? "Yearly" : "6 months",
                    displayPrice: product.localizedPriceString,
                    periodLabel: isYearly ? "per year" : "per 6 months",
                    trialLabel: trialLabel,
                    perMonthLabel: product.localizedPricePerMonth.map { "\($0)/month" }
                ))
                index[id] = package
            }
            // 6 months first, yearly (the highlighted one) last.
            premiumPlans = loaded.sorted { !$0.isYearly && $1.isYearly }
            premiumPackagesById = index
        } catch {
            log.error("Loading premium offering failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    #if canImport(RevenueCat)
    /// "7 days free" / "1 month free" from a trial period.
    private static func trialLabel(_ period: SubscriptionPeriod) -> String {
        let days = period.unit == .week ? period.value * 7 : (period.unit == .day ? period.value : nil)
        if let days { return "\(days) days free" }
        let unit = period.unit == .month ? "month" : "year"
        return "\(period.value) \(unit)\(period.value == 1 ? "" : "s") free"
    }

    private func applyCustomerInfo(_ info: CustomerInfo) {
        hasPremiumEntitlement = info.entitlements[PremiumPlan.entitlementId]?.isActive == true
    }
    #endif

    /// Refresh the local entitlement (on launch and when the paywall opens).
    func refreshEntitlement() async {
        #if DEBUG
        if isDemo { return }
        #endif
        #if canImport(RevenueCat)
        guard isAvailable else { return }
        if let info = try? await Purchases.shared.customerInfo() {
            applyCustomerInfo(info)
        }
        #endif
    }

    /// Run the subscription purchase. Returns true when the user subscribed
    /// (or started the trial). Never writes `premiumUntil`: the webhook does,
    /// and it reaches both partners through their user-document listeners.
    @discardableResult
    func subscribe(_ plan: PremiumPlan) async throws -> Bool {
        #if DEBUG
        if isDemo {
            subscribingPlanId = plan.id
            defer { subscribingPlanId = nil }
            try? await Task.sleep(for: .seconds(0.9))
            hasPremiumEntitlement = true
            return true
        }
        #endif
        #if canImport(RevenueCat)
        guard let package = premiumPackagesById[plan.id] else { return false }

        subscribingPlanId = plan.id
        defer { subscribingPlanId = nil }

        // The webhook keys premium on this uid; never subscribe anonymously.
        await ensureIdentified()

        let result = try await Purchases.shared.purchase(package: package)
        guard !result.userCancelled else { return false }
        applyCustomerInfo(result.customerInfo)
        return true
        #else
        return false
        #endif
    }

    /// Open subscription management for the store the purchase came from
    /// (App Store, or RevenueCat's Test Store in Debug). Returns false when
    /// RevenueCat couldn't, so the caller can fall back to Apple's sheet.
    func showManageSubscriptions() async -> Bool {
        #if canImport(RevenueCat)
        guard isAvailable else { return false }
        #if DEBUG
        if isDemo { return false }
        #endif
        do {
            try await Purchases.shared.showManageSubscriptions()
            return true
        } catch {
            log.error("showManageSubscriptions failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        #else
        return false
        #endif
    }

    /// Restore a subscription bought on another device or account. Returns
    /// whether the entitlement is active afterwards.
    @discardableResult
    func restorePurchases() async throws -> Bool {
        #if DEBUG
        if isDemo {
            isRestoring = true
            defer { isRestoring = false }
            try? await Task.sleep(for: .seconds(0.6))
            return hasPremiumEntitlement
        }
        #endif
        #if canImport(RevenueCat)
        guard isAvailable else { return false }
        isRestoring = true
        defer { isRestoring = false }
        await ensureIdentified()
        let info = try await Purchases.shared.restorePurchases()
        applyCustomerInfo(info)
        return hasPremiumEntitlement
        #else
        return false
        #endif
    }
}
