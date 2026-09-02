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
//  ── Before this compiles ──
//  The RevenueCat SDK is not yet a dependency. Everything that touches it is
//  behind `#if canImport(RevenueCat)`, so the app builds and runs without it —
//  treat packs simply do not appear. To turn them on:
//    Xcode → File → Add Package Dependencies…
//    → https://github.com/RevenueCat/purchases-ios  (product: RevenueCat)
//  and set `publicSDKKey` below.
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
}

// MARK: - Service

@MainActor
final class PurchaseService: ObservableObject {
    static let shared = PurchaseService()

    /// RevenueCat's *public* SDK key (starts with `appl_`). Publishable — it is
    /// designed to ship inside the app binary. Never put a secret key here.
    private static let publicSDKKey = "appl_REPLACE_ME"

    @Published private(set) var packs: [TreatPack] = []
    @Published private(set) var isLoading = false
    @Published private(set) var purchasingProductId: String?

    /// True from a completed purchase until the server-credited balance lands.
    @Published private(set) var isAwaitingCredit = false

    private let log = Logger(subsystem: Logger.subsystem, category: "purchases")

    #if canImport(RevenueCat)
    /// Product id → the RevenueCat package to buy, kept out of `TreatPack`.
    private var packagesByProductId: [String: Package] = [:]
    #endif

    private init() {}

    /// Whether treat packs can be offered at all. False until the SDK is added
    /// and a real key is set, which is what keeps the Shop from showing a
    /// buy button that cannot work.
    var isAvailable: Bool {
        #if canImport(RevenueCat)
        return Self.publicSDKKey != "appl_REPLACE_ME"
        #else
        return false
        #endif
    }

    // MARK: - Lifecycle

    /// Call once at launch, after `FirebaseApp.configure()`.
    func configure() {
        #if canImport(RevenueCat)
        guard isAvailable else {
            log.notice("RevenueCat SDK key not set — treat packs disabled")
            return
        }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: Self.publicSDKKey)
        #endif
    }

    /// Tie RevenueCat's app_user_id to the Firebase uid, so the webhook's
    /// `app_user_id` is the same string as the `users/{uid}` document id.
    /// Without this the purchase arrives under an anonymous id and the
    /// webhook has no user to credit.
    func login(uid: String) async {
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
        #if canImport(RevenueCat)
        guard isAvailable, let uid = Auth.auth().currentUser?.uid else { return }
        guard Purchases.shared.appUserID != uid else { return }
        await login(uid: uid)
        #endif
    }

    /// Detach the account on sign-out so the next user on this device does not
    /// inherit the previous one's purchase identity.
    func logOut() async {
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
    /// caller shows a pending state and waits for the listener to catch up.
    @discardableResult
    func buy(_ pack: TreatPack) async throws -> Bool {
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
        isAwaitingCredit = true
        return true
        #else
        return false
        #endif
    }

    /// Called by the Shop once the credited balance shows up (or gives up).
    func creditSettled() {
        isAwaitingCredit = false
    }
}
