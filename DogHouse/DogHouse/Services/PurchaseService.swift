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
//  See TREAT_PACKS_SETUP.md.
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
    /// in TREAT_PACKS_SETUP.md ($0.99 / $2.99 / $4.99). Worded without a
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

    #if canImport(RevenueCat)
    /// Product id → the RevenueCat package to buy, kept out of `TreatPack`.
    private var packagesByProductId: [String: Package] = [:]
    #endif

    private init() {}

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
    #endif

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
            _ = try await Purchases.shared.logIn(uid)
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
}
