//
//  AuthService.swift
//  DogHouse
//
//  Firebase Auth + Firestore user documents with real-time snapshot listener.
//

import SwiftUI
import Combine
import OSLog
import AuthenticationServices
import CryptoKit
import GoogleSignIn
import FirebaseAuth
import FirebaseCrashlytics
import FirebaseFirestore

@MainActor
class AuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isAuthInitialized = false
    @Published var userProfile: UserProfile?
    @Published var partnerProfile: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// This account's pairing code, read from the owner-only private
    /// document. Views must use this rather than `userProfile.partnerCode`,
    /// which is a legacy field that no longer exists on new accounts.
    @Published var partnerCode: String?
    /// Engagement nudges (Profile → Reminders). Server treats absent as on.
    @Published var remindersEnabled = true
    private var lastActivityWrite: Date?

    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var userDocListener: ListenerRegistration?
    private var partnerDocListener: ListenerRegistration?
    private var privateDocListener: ListenerRegistration?
    private var fcmTokenObserver: NSObjectProtocol?
    private let fs = FirebaseService.shared

    init() {
        #if DEBUG
        if Self.isDemo {
            configureDemo()
            return
        }
        #endif
        // Firebase restores the signed-in user from the keychain synchronously
        // at startup. Seed from it so there is never a frame — nor a fallback
        // path — on which a signed-in user is treated as signed out.
        isAuthenticated = Auth.auth().currentUser != nil
        listenToAuthState()
        listenForFCMTokenRefresh()
    }

    #if DEBUG
    // MARK: - Demo Mode (debug builds only)

    /// Launch the app with the `-demoOnboarding` argument to walk the
    /// onboarding screens and the live tour with fake data and no account.
    /// Add `-demoHome` to skip straight to Home in the all-clear state.
    /// No auth listener is attached and the profile mutations below are
    /// applied locally, so nothing reaches Firebase. Task negotiation is
    /// skipped (it needs a real second partner).
    static let isDemo = ProcessInfo.processInfo.arguments.contains("-demoOnboarding")

    private func configureDemo() {
        isAuthInitialized = true
        isAuthenticated = true
        partnerCode = "DEMO42"
        // A demo doghouse stint skips straight to Home: the point of it is the
        // scene, not the onboarding, and the tour would sit on top of it.
        let straightToHome = DoghouseService.demoDoghouseHours != nil
            || ProcessInfo.processInfo.arguments.contains("-demoHome")
        userProfile = UserProfile(
            id: "demo_me", displayName: straightToHome ? "Harrison" : "", avatarId: straightToHome ? "dog_1" : nil,
            partnerCode: nil, partnerId: straightToHome ? "demo_partner" : nil, immunityUntil: nil,
            friendIds: [], createdAt: Date(), fcmToken: nil, graceCharges: UserProfile.maxGraceCharges,
            lastGraceRecharge: Date(), tourComplete: straightToHome, onboardingComplete: straightToHome
        )
        partnerProfile = UserProfile(
            id: "demo_partner", displayName: "Sam", avatarId: "dog_3", partnerCode: nil,
            partnerId: "demo_me", immunityUntil: nil, friendIds: [], createdAt: Date(),
            fcmToken: nil, graceCharges: UserProfile.maxGraceCharges,
            lastGraceRecharge: Date(), tourComplete: true, onboardingComplete: true
        )
    }
    #endif

    isolated deinit {
        if let handle = authStateListener {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        userDocListener?.remove()
        partnerDocListener?.remove()
        privateDocListener?.remove()
        if let observer = fcmTokenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Auth State Listener

    private func listenForFCMTokenRefresh() {
        fcmTokenObserver = NotificationCenter.default.addObserver(
            forName: .fcmTokenRefreshed,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let token = notification.userInfo?["token"] as? String else { return }
            Task { @MainActor [weak self] in
                guard let self, let uid = Auth.auth().currentUser?.uid else { return }
                await self.writeFCMToken(token, uid: uid)
            }
        }
    }

    /// Push tokens live on the owner-only private document, never on the
    /// publicly-gettable user document.
    private func writeFCMToken(_ token: String, uid: String) async {
        do {
            try await fs.privateDataDocument(for: uid)
                .setData(["fcmToken": token], merge: true)
        } catch {
            Logger.push.error("FCM token write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func listenToAuthState() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            // Firebase calls this on the main thread
            guard let self else { return }
            MainActor.assumeIsolated {
                self.isAuthInitialized = true
                if let user {
                    self.isAuthenticated = true
                    // Ties a crash report to an account without logging any
                    // personal data — the uid is opaque.
                    Crashlytics.crashlytics().setUserID(user.uid)
                    self.listenToUserDocument(userId: user.uid)
                    self.listenToPrivateDocument(userId: user.uid)
                    // Purchases must be attributed to the Firebase uid — the
                    // webhook credits users/{app_user_id}.
                    Task { await PurchaseService.shared.login(uid: user.uid) }
                } else {
                    Crashlytics.crashlytics().setUserID("")
                    Task { await PurchaseService.shared.logOut() }
                    self.isAuthenticated = false
                    self.userProfile = nil
                    self.partnerCode = nil
                    self.userDocListener?.remove()
                    self.userDocListener = nil
                    self.privateDocListener?.remove()
                    self.privateDocListener = nil
                    // The partner listener used to survive sign-out. Signing
                    // in as someone else then showed the previous account's
                    // partner until their own listener happened to fire.
                    self.partnerDocListener?.remove()
                    self.partnerDocListener = nil
                    self.partnerProfile = nil
                }
            }
        }
    }

    /// Real-time listener on the owner-only private document (pairing code,
    /// push token). Nothing here is readable by any other account.
    private func listenToPrivateDocument(userId: String) {
        privateDocListener?.remove()
        privateDocListener = fs.privateDataDocument(for: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        Logger.data.error("Private doc listener: \(error.localizedDescription, privacy: .public)")
                        return
                    }
                    self.partnerCode = snapshot?.data()?["partnerCode"] as? String
                    self.remindersEnabled = snapshot?.data()?["remindersEnabled"] as? Bool ?? true
                }
            }
    }

    /// Heartbeat for the engagement nudges: when this account last had the
    /// app open, and in which time zone. Throttled so a foreground/background
    /// flurry costs one write. Absent on the server means "unknown", and
    /// unknown accounts get no re-engagement nudges at all.
    func recordActivity() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if let last = lastActivityWrite, Date().timeIntervalSince(last) < 15 * 60 { return }
        lastActivityWrite = Date()
        do {
            try await fs.privateDataDocument(for: uid).setData([
                "lastActiveAt": FieldValue.serverTimestamp(),
                "timeZone": TimeZone.current.identifier,
            ], merge: true)
        } catch {
            Logger.data.error("Activity write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setRemindersEnabled(_ enabled: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        remindersEnabled = enabled
        do {
            try await fs.privateDataDocument(for: uid)
                .setData(["remindersEnabled": enabled], merge: true)
        } catch {
            Logger.data.error("Reminders toggle write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One-time migration for accounts created before the pairing code and
    /// push token moved off the public user document. Runs on the first
    /// profile load after updating; the security rules reject any write that
    /// leaves either key in place, so this must land before other profile
    /// writes succeed. A daily server-side sweep (backfillPrivateUserData)
    /// covers accounts that never open the app again.
    private func migrateLegacyPrivateFields(_ profile: UserProfile) async {
        guard profile.partnerCode != nil || profile.fcmToken != nil else { return }

        var privateFields: [String: Any] = [:]
        if let code = profile.partnerCode { privateFields["partnerCode"] = code }
        if let token = profile.fcmToken { privateFields["fcmToken"] = token }

        do {
            if !privateFields.isEmpty {
                try await fs.privateDataDocument(for: profile.id)
                    .setData(privateFields, merge: true)
            }
            try await fs.usersCollection.document(profile.id).updateData([
                "partnerCode": FieldValue.delete(),
                "fcmToken": FieldValue.delete()
            ])
            Logger.data.info("Migrated legacy private fields off public profile")
        } catch {
            Logger.data.error("Private field migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Real-time listener on the user's Firestore document
    private func listenToUserDocument(userId: String) {
        userDocListener?.remove()
        userDocListener = fs.usersCollection.document(userId).addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor [weak self] in
                guard let self, let snapshot else { return }

                // Signed in with no profile document. Normally impossible, but a
                // bootstrap that failed halfway (lost connection right after the
                // Auth account was created) would otherwise strand the account
                // on the pairing screen forever, with no code and no way to mint
                // one. Recreate it instead.
                //
                // Only trust the server on this. Offline, Firestore answers a
                // never-cached document with an `exists == false` snapshot
                // straight from the (empty) cache; acting on that would try to
                // re-bootstrap a perfectly good account every time it launches
                // without a connection.
                guard snapshot.exists else {
                    guard !snapshot.metadata.isFromCache else { return }
                    await self.recoverMissingProfile(userId: userId)
                    return
                }
                do {
                    let profile = try self.fs.decode(UserProfile.self, from: snapshot)
                    self.userProfile = profile

                    // Relocate secrets off the public document before any
                    // other profile write is attempted (rules reject writes
                    // that leave them in place).
                    await self.migrateLegacyPrivateFields(profile)

                    // Legacy migration: existing paired users skip avatar & tour
                    // but still go through task negotiation
                    if profile.partnerId != nil && profile.partnerId != "skipped" && profile.onboardingComplete == nil {
                        Task {
                            var updates: [String: Any] = ["tourComplete": true]
                            if profile.avatarId == nil {
                                updates["avatarId"] = "dog_1"
                            }
                            try? await self.fs.usersCollection.document(profile.id).updateData(updates)
                        }
                    }

                    // Start listening to partner if we have one
                    if let partnerId = profile.partnerId, partnerId != "skipped" {
                        self.listenToPartnerDocument(partnerId: partnerId)
                    } else {
                        self.partnerDocListener?.remove()
                        self.partnerProfile = nil
                    }
                } catch {
                    Logger.data.error("User profile decode failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Real-time listener on the partner's Firestore document
    private func listenToPartnerDocument(partnerId: String) {
        // Don't re-attach if already listening to the same partner
        if partnerProfile?.id == partnerId { return }
        partnerDocListener?.remove()
        partnerDocListener = fs.usersCollection.document(partnerId).addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor [weak self] in
                guard let self, let snapshot, snapshot.exists else { return }
                do {
                    let profile = try self.fs.decode(UserProfile.self, from: snapshot)
                    self.partnerProfile = profile

                    // Only clear our partnerId if the partner has actively paired with
                    // someone else. A nil partnerId means they haven't entered our code yet,
                    // which is normal during one-sided pairing — don't undo our own write.
                    if let myUid = Auth.auth().currentUser?.uid,
                       let theirPartnerId = profile.partnerId,
                       theirPartnerId != "skipped",
                       theirPartnerId != myUid {
                        try? await self.fs.usersCollection.document(myUid).updateData(
                            ["partnerId": FieldValue.delete()]
                        )
                    }
                } catch {
                    Logger.data.error("Partner profile decode failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Account Bootstrap

    /// Create this account's Firestore documents if they don't exist yet.
    ///
    /// Every sign-in path must run this, not just email sign-up. Apple and
    /// Google sign-in produce a Firebase Auth user and nothing else — no profile
    /// document, no private document, and above all no `partnerCodes` claim. An
    /// account in that state opens straight onto the pairing screen showing
    /// "------" where its code should be, with nothing in the app able to mint
    /// one: a dead end.
    ///
    /// Idempotent, and that matters beyond efficiency: `partnerCode` is
    /// immutable by security rule, so re-issuing one for a returning user would
    /// be rejected outright.
    @discardableResult
    private func bootstrapProfileIfNeeded(uid: String, displayName: String) async throws -> Bool {
        let userRef = fs.usersCollection.document(uid)
        if try await userRef.getDocument().exists { return false }

        let partnerCode = generatePartnerCode()

        // partnerCode and fcmToken are deliberately absent here — they go to
        // the owner-only private document below.
        let profile = UserProfile(
            id: uid,
            displayName: displayName,
            avatarId: nil,
            partnerCode: nil,
            partnerId: nil,
            immunityUntil: nil,
            friendIds: [],
            createdAt: Date(),
            fcmToken: nil,
            graceCharges: UserProfile.maxGraceCharges,
            lastGraceRecharge: Date(),
            tourComplete: false,
            onboardingComplete: false
        )

        // Batch write: public profile + private secrets + partner code claim
        let batch = fs.db.batch()
        batch.setData(try fs.encoder.encode(profile), forDocument: userRef)

        var privateFields: [String: Any] = ["partnerCode": partnerCode]
        if let token = UserDefaults.standard.string(forKey: "fcmToken") {
            privateFields["fcmToken"] = token
        }
        batch.setData(privateFields, forDocument: fs.privateDataDocument(for: uid))

        batch.setData(["userId": uid], forDocument: fs.partnerCodesCollection.document(partnerCode))
        try await batch.commit()
        return true
    }

    /// Guards against re-entering recovery while a bootstrap write is in flight.
    private var isRecoveringProfile = false

    private func recoverMissingProfile(userId: String) async {
        // `userProfile == nil` is what separates "never had one" from "just lost
        // one". Account deletion writes deletionRequests/{uid} and signs out
        // asynchronously, so onDeletionRequest can wipe the user document while
        // this listener is still attached — without this check, recovery would
        // helpfully recreate the profile, the private document and a fresh
        // partnerCodes claim for an account that is being deleted.
        guard !isRecoveringProfile,
              userProfile == nil,
              let user = Auth.auth().currentUser,
              user.uid == userId else { return }
        isRecoveringProfile = true
        defer { isRecoveringProfile = false }

        do {
            let created = try await bootstrapProfileIfNeeded(
                uid: userId,
                displayName: (user.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if created {
                Logger.data.info("Recreated a missing profile document after an interrupted sign-up")
            }
        } catch {
            Logger.data.error("Profile recovery failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Set the name shown to the partner. Used by the onboarding name step,
    /// which appears when a provider gave us no usable name.
    func updateDisplayName(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        #if DEBUG
        if Self.isDemo {
            userProfile?.displayName = trimmed
            return
        }
        #endif
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await fs.usersCollection.document(uid).updateData(["displayName": trimmed])
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, displayName: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        try await bootstrapProfileIfNeeded(uid: result.user.uid, displayName: displayName)

        // The snapshot listener will pick up userProfile automatically
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        try await Auth.auth().signIn(withEmail: email, password: password)
        // Auth state listener handles setting isAuthenticated and attaching user doc listener

        // Update FCM token if available
        if let uid = Auth.auth().currentUser?.uid,
           let fcmToken = UserDefaults.standard.string(forKey: "fcmToken") {
            await writeFCMToken(fcmToken, uid: uid)
        }
    }

    // MARK: - Password Reset

    /// Email a password reset link. With Firebase's email-enumeration
    /// protection on (the default for new projects) this succeeds silently
    /// for unknown addresses, so callers should word the confirmation as
    /// "if an account exists" rather than as a promise.
    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    // MARK: - App Tour

    /// Record that the live tour has been seen. A replay from Profile finds
    /// the flag already set and writes nothing.
    func markTourComplete() async {
        guard let uid = Auth.auth().currentUser?.uid,
              userProfile?.isTourComplete != true else { return }
        do {
            try await fs.usersCollection.document(uid).updateData(["tourComplete": true])
        } catch {
            Logger.data.error("tourComplete write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Sign in with Apple

    /// Raw nonce for the authorization currently in flight.
    private var appleSignInNonce: String?

    /// Configure the Apple authorization request.
    ///
    /// Apple signs the *hash* of the nonce into the identity token; Firebase
    /// re-derives it from the raw value we hand it later. Skipping this is what
    /// lets a stolen identity token be replayed against the project, so both
    /// halves have to line up — hashed on the request, raw on the credential.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        appleSignInNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func completeAppleSignIn(_ authorization: ASAuthorization) async throws {
        isLoading = true
        defer { isLoading = false }

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce = appleSignInNonce else {
            throw NSError(domain: "AuthService", code: -10, userInfo: [
                NSLocalizedDescriptionKey: "Apple didn't return a usable sign-in token. Please try again."
            ])
        }
        appleSignInNonce = nil

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: credential.fullName
        )
        let result = try await Auth.auth().signIn(with: firebaseCredential)

        // Apple sends the name on the FIRST authorization only. If it isn't
        // captured now it is gone for good, and the account keeps whatever name
        // it was created with.
        try await bootstrapProfileIfNeeded(
            uid: result.user.uid,
            displayName: Self.formattedName(credential.fullName)
        )
        await syncTokenAfterSignIn()
    }

    // MARK: - Sign in with Google

    /// Whether to offer the Google button at all.
    ///
    /// `GoogleService-Info.plist` only carries `CLIENT_ID` once Google is enabled
    /// as a sign-in provider for this app in the Firebase console. Without it
    /// there is nothing to configure the SDK with, so the button is hidden
    /// rather than shown and broken.
    static var isGoogleSignInConfigured: Bool { googleClientID != nil }

    private static var googleClientID: String? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientID = plist["CLIENT_ID"] as? String,
              !clientID.isEmpty
        else { return nil }
        return clientID
    }

    func signInWithGoogle(presenting: UIViewController) async throws {
        isLoading = true
        defer { isLoading = false }

        guard let clientID = Self.googleClientID else {
            throw NSError(domain: "AuthService", code: -11, userInfo: [
                NSLocalizedDescriptionKey: "Google sign-in isn't set up for this app yet."
            ])
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let googleResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
        guard let idToken = googleResult.user.idToken?.tokenString else {
            throw NSError(domain: "AuthService", code: -12, userInfo: [
                NSLocalizedDescriptionKey: "Google didn't return a usable sign-in token. Please try again."
            ])
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: googleResult.user.accessToken.tokenString
        )
        let authResult = try await Auth.auth().signIn(with: credential)

        try await bootstrapProfileIfNeeded(
            uid: authResult.user.uid,
            displayName: (googleResult.user.profile?.name ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        await syncTokenAfterSignIn()
    }

    // MARK: - OAuth Helpers

    /// A name we're willing to show the partner, or "" to let the onboarding
    /// name step ask for one. Deliberately no email-derived fallback: with Hide
    /// My Email that yields a random string, which is worse than asking.
    private static func formattedName(_ components: PersonNameComponents?) -> String {
        guard let components else { return "" }
        return PersonNameComponentsFormatter()
            .string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func randomNonceString(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<length).map { _ in UInt8.random(in: 0...255) }
        }
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Attach this device's push token to the account that just signed in.
    private func syncTokenAfterSignIn() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let token = UserDefaults.standard.string(forKey: "fcmToken") else { return }
        await writeFCMToken(token, uid: uid)
    }

    // MARK: - Sign Out

    func signOut() {
        let uid = Auth.auth().currentUser?.uid
        Task {
            // Detach this device's push token from the account so it stops
            // receiving notifications for a profile it's no longer signed into.
            // Bounded at 2s so an offline user can still sign out.
            if let uid {
                let ref = fs.privateDataDocument(for: uid)
                try? await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await ref.updateData(["fcmToken": FieldValue.delete()]) }
                    group.addTask { try await Task.sleep(for: .seconds(2)) }
                    try await group.next()
                    group.cancelAll()
                }
            }
            try? Auth.auth().signOut()
            // Auth state listener handles resetting isAuthenticated and userProfile
        }
    }

    /// Whether this account signed in with Apple. App Store Review Guideline
    /// 5.1.1(v) requires such accounts to have their Sign in with Apple token
    /// revoked as part of account deletion.
    var usesAppleSignIn: Bool {
        Auth.auth().currentUser?.providerData.contains { $0.providerID == "apple.com" } ?? false
    }

    /// Request permanent account deletion. Writes a deletion request that the
    /// onDeletionRequest Cloud Function processes (wipes all data + the Auth
    /// account with admin privileges), then signs out locally.
    ///
    /// - Parameter appleAuthorizationCode: a fresh code from Sign in with
    ///   Apple, used to revoke Apple's token first. Revocation failing must
    ///   not block deletion — the user's right to delete beats the paperwork —
    ///   so it is logged and the wipe proceeds. Requires the Apple provider in
    ///   the Firebase console to be configured with the Services ID, team ID,
    ///   key ID and private key; without those Firebase cannot call Apple.
    func deleteAccount(appleAuthorizationCode: String? = nil) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        if let code = appleAuthorizationCode {
            do {
                try await Auth.auth().revokeToken(withAuthorizationCode: code)
                Logger.auth.info("Revoked Sign in with Apple token before deletion")
            } catch {
                Logger.auth.error("Apple token revocation failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        try await fs.db.collection("deletionRequests").document(uid).setData([
            "requestedAt": Timestamp(date: Date())
        ])
        signOut()
    }

    // MARK: - Pair With Partner

    func pairWithPartner(code: String) async throws {
        isLoading = true
        defer { isLoading = false }

        #if DEBUG
        if Self.isDemo {
            try? await Task.sleep(for: .seconds(0.6))
            userProfile?.partnerId = "demo_partner"
            return
        }
        #endif

        guard let myUid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "AuthService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        // Look up the partner code
        let codeDoc = try await fs.partnerCodesCollection.document(code.uppercased()).getDocument()
        guard let partnerUid = codeDoc.data()?["userId"] as? String else {
            throw NSError(domain: "AuthService", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid partner code"])
        }

        guard partnerUid != myUid else {
            throw NSError(domain: "AuthService", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "You cannot pair with yourself"])
        }

        // Check partner is not already paired with someone else.
        // Allow the case where partner already points to us — this happens when both
        // users enter each other's codes simultaneously and the partner's write landed first.
        let partnerDoc = try await fs.usersCollection.document(partnerUid).getDocument()
        let fetchedPartner = try fs.decode(UserProfile.self, from: partnerDoc)
        if let existingPartner = fetchedPartner.partnerId,
           existingPartner != "skipped",
           existingPartner != myUid {
            throw NSError(domain: "AuthService", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "This user is already paired with someone"])
        }

        // Only write to our own document. Writing to the partner's document requires
        // cross-user Firestore permissions which are typically restricted by security rules,
        // causing the batch to fail silently and the view to never advance.
        // Each user entering the other's code handles mutual pairing independently.
        try await fs.usersCollection.document(myUid).updateData(["partnerId": partnerUid])

        // Snapshot listener will update userProfile.partnerId → OnboardingContainerView auto-advances
    }

    // MARK: - Update Avatar

    func updateAvatar(id: String) {
        #if DEBUG
        if Self.isDemo {
            // Demo skips task negotiation and goes straight to the live tour.
            userProfile?.avatarId = id
            userProfile?.onboardingComplete = true
            return
        }
        #endif
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Optimistic local update for snappy UI
        if var profile = userProfile {
            profile.avatarId = id
            userProfile = profile
        }
        Task {
            try? await fs.usersCollection.document(uid).updateData(["avatarId": id])
        }
    }

    // MARK: - Un-pair

    func unpairFromPartner() async throws {
        guard let myUid = Auth.auth().currentUser?.uid,
              let partnerId = userProfile?.partnerId,
              partnerId != "skipped" else { return }

        // Only clear our own partnerId. The partner's listener will detect that
        // our partnerId no longer points to them and will clear their own automatically.
        try await fs.usersCollection.document(myUid).updateData(["partnerId": FieldValue.delete()])

        partnerDocListener?.remove()
        partnerProfile = nil
    }

    // MARK: - Helpers

    private func generatePartnerCode() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // No O/0/I/1
        return String((0..<6).map { _ in characters.randomElement()! })
    }

    /// Convert Firebase error codes to user-friendly messages.
    ///
    /// Also logs the raw domain and code: the returned string is deliberately
    /// vague, and without this a provider-side misconfiguration (a sign-in
    /// method left disabled in the Firebase console, code 17006) is
    /// indistinguishable on screen from a typo'd password.
    static func friendlyError(_ error: Error) -> String {
        let nsError = error as NSError
        Logger.auth.error(
            "Auth failure: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)"
        )
        switch nsError.code {
        case 17006:
            // ERROR_OPERATION_NOT_ALLOWED — the provider is switched off for
            // this Firebase project. No client change can fix it.
            return "This sign-in method isn't enabled for DogHouse yet. Please try another way to sign in."
        case 17012:
            // ERROR_ACCOUNT_EXISTS_WITH_DIFFERENT_CREDENTIAL
            return "You already have an account with this email. Sign in the way you did the first time."
        case 17004:
            return "Those sign-in details weren't accepted. Please try again."
        case 17005:
            // ERROR_USER_DISABLED
            return "This account has been disabled. Please contact support."
        case 17014:
            // ERROR_REQUIRES_RECENT_LOGIN
            return "Please sign out and back in, then try that again."
        case 17008: return "Please enter a valid email address."
        case 17009: return "Incorrect password. Please try again."
        case 17011: return "No account found with this email."
        case 17007: return "An account with this email already exists."
        case 17026: return "Password must be at least 6 characters."
        case 17020: return "No internet connection. Please check your network."
        case 17010: return "Too many attempts. Please try again later."
        default:
            let desc = nsError.localizedDescription
            // Strip Firebase prefix if present
            if desc.contains("]") {
                return String(desc.split(separator: "]").last ?? Substring(desc)).trimmingCharacters(in: .whitespaces)
            }
            return desc
        }
    }
}
