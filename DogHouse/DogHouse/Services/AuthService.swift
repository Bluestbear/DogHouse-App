//
//  AuthService.swift
//  DogHouse
//
//  Firebase Auth + Firestore user documents with real-time snapshot listener.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class AuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isAuthInitialized = false
    @Published var userProfile: UserProfile?
    @Published var partnerProfile: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var userDocListener: ListenerRegistration?
    private var partnerDocListener: ListenerRegistration?
    private var fcmTokenObserver: NSObjectProtocol?
    private let fs = FirebaseService.shared

    init() {
        listenToAuthState()
        listenForFCMTokenRefresh()
    }

    deinit {
        if let handle = authStateListener {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        userDocListener?.remove()
        partnerDocListener?.remove()
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
                try? await self.fs.usersCollection.document(uid).updateData(["fcmToken": token])
            }
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
                    self.listenToUserDocument(userId: user.uid)
                } else {
                    self.isAuthenticated = false
                    self.userProfile = nil
                    self.userDocListener?.remove()
                    self.userDocListener = nil
                }
            }
        }
    }

    /// Real-time listener on the user's Firestore document
    private func listenToUserDocument(userId: String) {
        userDocListener?.remove()
        userDocListener = fs.usersCollection.document(userId).addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor [weak self] in
                guard let self, let snapshot, snapshot.exists else { return }
                do {
                    let profile = try self.fs.decode(UserProfile.self, from: snapshot)
                    self.userProfile = profile

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
                    print("Failed to decode user profile: \(error)")
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
                    print("Failed to decode partner profile: \(error)")
                }
            }
        }
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, displayName: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let uid = result.user.uid
        let partnerCode = generatePartnerCode()

        let profile = UserProfile(
            id: uid,
            displayName: displayName,
            avatarId: nil,
            partnerCode: partnerCode,
            partnerId: nil,
            immunityUntil: nil,
            friendIds: [],
            createdAt: Date(),
            fcmToken: UserDefaults.standard.string(forKey: "fcmToken"),
            graceCharges: UserProfile.maxGraceCharges,
            lastGraceRecharge: Date(),
            tourComplete: false,
            onboardingComplete: false
        )

        // Batch write: user document + partner code claim
        let batch = fs.db.batch()
        batch.setData(try fs.encoder.encode(profile), forDocument: fs.usersCollection.document(uid))
        batch.setData(["userId": uid], forDocument: fs.partnerCodesCollection.document(partnerCode))
        try await batch.commit()

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
            try? await fs.usersCollection.document(uid).updateData(["fcmToken": fcmToken])
        }
    }

    // MARK: - Sign Out

    func signOut() {
        let uid = Auth.auth().currentUser?.uid
        Task {
            // Detach this device's push token from the account so it stops
            // receiving notifications for a profile it's no longer signed into.
            // Bounded at 2s so an offline user can still sign out.
            if let uid {
                let ref = fs.usersCollection.document(uid)
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

    // MARK: - Pair With Partner

    func pairWithPartner(code: String) async throws {
        isLoading = true
        defer { isLoading = false }

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

    /// Convert Firebase error codes to user-friendly messages
    static func friendlyError(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
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
