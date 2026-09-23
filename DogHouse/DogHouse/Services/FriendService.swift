//
//  FriendService.swift
//  DogHouse
//
//  Couple-to-couple friendships. Couples link up with another couple's
//  code (either partner's code works); the server (addCoupleFriend
//  callable) validates both pairings and writes the link. Mock data
//  preserved for SwiftUI Previews.
//

import SwiftUI
import Combine
import OSLog
import FirebaseAuth
import FirebaseFirestore

/// A befriended couple: the other couple's key + both partners' profiles.
struct FriendCouple: Identifiable {
    var id: String { coupleKey }
    let coupleKey: String
    let members: [UserProfile]

    var displayName: String {
        members.map(\.displayName).joined(separator: " & ")
    }
}

class FriendService: ObservableObject {
    @Published var friendCouples: [FriendCouple] = []

    /// Why the list is empty, when it's empty for a reason. Shown in
    /// FriendsTabView: an OSLog line needs Console.app to read, which is no use
    /// during a two-phone test session.
    @Published var loadError: String?

    private(set) var userId: String
    private var partnerId: String?
    private let fs = FirebaseService.shared
    private var linksListener: ListenerRegistration?
    private var profileCache: [String: UserProfile] = [:]
    /// Bumped per rebuild so a slow, older rebuild can't overwrite a newer one
    private var rebuildGeneration = 0

    private var myCoupleKey: String? {
        guard let partnerId, partnerId != "skipped" else { return nil }
        return fs.coupleKey(userId1: userId, userId2: partnerId)
    }

    init(userId: String) {
        // Resolve real user ID from Firebase Auth when views pass "mock_user"
        var signedInUid = Auth.auth().currentUser?.uid
        #if DEBUG
        // `-demoFriends` shows the mock feed even on a sim that is signed in.
        if AuthService.isDemoFriends { signedInUid = nil }
        #endif
        if userId == "mock_user", let realUid = signedInUid {
            self.userId = realUid
        } else {
            self.userId = userId
        }

        // SwiftUI Preview guard — load mock data instead of hitting Firestore
        guard self.userId != "mock_user" else {
            loadMockData()
            return
        }

        Task { await resolvePartnerAndListen() }
    }

    isolated deinit {
        linksListener?.remove()
    }

    private func resolvePartnerAndListen() async {
        guard let doc = try? await fs.usersCollection.document(userId).getDocument() else {
            Logger.data.error("FriendService: couldn't read own profile; friend list will stay empty")
            return
        }
        configure(partnerId: doc.data()?["partnerId"] as? String)
    }

    /// Point the service at the current couple.
    ///
    /// The partner id used to be resolved exactly once, in `init`. Every couple
    /// this service can show is keyed off it, and `rebuildCouples` silently
    /// returns when it is nil — so a service constructed at a moment when the
    /// pairing wasn't readable yet (or which outlived an unpair/re-pair) showed
    /// an empty friends list for the rest of the app's lifetime, no matter what
    /// arrived on the listener. The view now feeds this from AuthService, which
    /// already tracks the pairing in real time.
    func configure(partnerId newPartnerId: String?) {
        let resolved = (newPartnerId == "skipped") ? nil : newPartnerId
        guard resolved != partnerId || linksListener == nil else { return }
        partnerId = resolved
        startListening()
    }

    private func startListening() {
        linksListener?.remove()
        linksListener = fs.db.collection("coupleFriendships")
            .whereField("memberIds", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // A denied or failed query is why the list would be empty;
                    // discarding this error is what made it undiagnosable.
                    if let error {
                        Logger.data.error("Couple friendships listener failed: \(error.localizedDescription, privacy: .public)")
                        self.loadError = "Couldn't load your friend couples: \(error.localizedDescription)"
                        return
                    }
                    self.loadError = nil
                    guard let docs = snapshot?.documents else { return }
                    await self.rebuildCouples(from: docs)
                }
            }
    }

    @MainActor
    private func rebuildCouples(from docs: [QueryDocumentSnapshot]) async {
        guard let myKey = myCoupleKey else {
            Logger.data.error("FriendService: \(docs.count) friendship(s) received but this couple's key is unknown — not paired yet?")
            if !docs.isEmpty {
                loadError = "You have \(docs.count) friend couple(s), but your own pairing isn't loaded yet. Reopen the app."
            }
            return
        }
        rebuildGeneration += 1
        let generation = rebuildGeneration
        var couples: [FriendCouple] = []
        var dropped = 0
        for doc in docs {
            let keys = doc.data()["coupleKeys"] as? [String] ?? []
            // A link from a previous pairing (the server dissolves these on
            // un-pair, but the listener can deliver first) is not ours to
            // show — skip it quietly rather than report it as broken.
            guard keys.contains(myKey) else {
                Logger.data.info("Friendship \(doc.documentID, privacy: .public) belongs to a former pairing — ignored")
                continue
            }
            guard let otherKey = keys.first(where: { $0 != myKey }) else {
                Logger.data.error("Friendship \(doc.documentID, privacy: .public) has no couple key other than mine")
                dropped += 1
                continue
            }
            let otherIds = otherKey.split(separator: "_").map(String.init)
            let profiles: [UserProfile]
            do {
                profiles = try await fetchProfiles(for: otherIds)
            } catch {
                Logger.data.error("Couldn't load friend couple profiles: \(error.localizedDescription, privacy: .public)")
                dropped += 1
                continue
            }
            // Show the couple even if only one profile came back. Dropping the
            // whole row when a lookup fails is indistinguishable, on screen,
            // from never having added them.
            guard !profiles.isEmpty else {
                Logger.data.error("Friend couple \(otherKey, privacy: .public) resolved to zero profiles")
                dropped += 1
                continue
            }
            couples.append(FriendCouple(coupleKey: otherKey, members: profiles))
        }
        // Two snapshots close together (add, then the listener's echo) run
        // two rebuilds; the profile fetches can finish out of order.
        guard generation == rebuildGeneration else { return }
        friendCouples = couples.sorted { $0.displayName < $1.displayName }

        // A link that exists but can't be turned into a row is exactly the
        // "it said it worked but nothing happened" case. Say so on screen.
        loadError = dropped > 0
            ? "\(dropped) friend couple(s) couldn't be loaded. Please try again."
            : nil
    }

    // MARK: - Actions (server-validated)

    /// Link with another couple using either partner's code.
    func addCouple(code: String) async throws {
        try await CloudFunctions.shared.call("addCoupleFriend", ["code": code.uppercased()])
        // The listener normally delivers the new link within a moment. Re-reading
        // once here means a successful add still shows up even if the listener
        // isn't healthy — "it said it worked but they never appeared" is the one
        // outcome this screen must not have.
        await refresh()
    }

    /// One-shot re-read of this couple's friendships.
    func refresh() async {
        do {
            let snapshot = try await fs.db.collection("coupleFriendships")
                .whereField("memberIds", arrayContains: userId)
                .getDocuments()
            await rebuildCouples(from: snapshot.documents)
        } catch {
            Logger.data.error("Friend couples refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func removeCouple(_ couple: FriendCouple) async throws {
        try await CloudFunctions.shared.call("removeCoupleFriend", ["coupleKey": couple.coupleKey])
        await MainActor.run {
            friendCouples.removeAll { $0.coupleKey == couple.coupleKey }
        }
    }

    // MARK: - Profile lookup (also used by the jailbreak vote screen)

    func fetchProfiles(for userIds: [String]) async throws -> [UserProfile] {
        if userId == "mock_user" {
            return friendCouples.flatMap(\.members).filter { userIds.contains($0.id) }
        }
        guard !userIds.isEmpty else { return [] }

        var results: [UserProfile] = []
        var toFetch: [String] = []
        for id in userIds {
            if let cached = profileCache[id] { results.append(cached) }
            else { toFetch.append(id) }
        }

        // Fetched one document at a time, in parallel, rather than with an
        // `in` query. The security rules deny `list` on /users so that no
        // account can enumerate the user table; single-document `get` by a
        // known uid is what remains permitted. Friend couples are small
        // (2 uids per couple), so the fan-out is trivial.
        // Only the network fetch happens off the main actor; decoding stays
        // here, because the model's Decodable conformance is main-actor
        // isolated under the module's default isolation.
        let snapshots: [DocumentSnapshot] = try await withThrowingTaskGroup(
            of: DocumentSnapshot?.self
        ) { group in
            let usersCollection = fs.usersCollection
            for id in toFetch {
                group.addTask {
                    let doc = try await usersCollection.document(id).getDocument()
                    return doc.exists ? doc : nil
                }
            }
            var collected: [DocumentSnapshot] = []
            for try await doc in group {
                if let doc { collected.append(doc) }
            }
            return collected
        }

        let fetched = snapshots.compactMap {
            try? fs.decode(UserProfile.self, from: $0)
        }
        for profile in fetched {
            profileCache[profile.id] = profile
            results.append(profile)
        }
        return results
    }

    // MARK: - Mock Data (Preview only)

    private func loadMockData() {
        friendCouples = [
            FriendCouple(coupleKey: "friend_1_friend_1_partner", members: [
                UserProfile(id: "friend_1", displayName: "Jordan", avatarId: "dog_3",
                            partnerCode: "ABC123", partnerId: "friend_1_partner",
                            immunityUntil: nil, friendIds: [], createdAt: Date(), fcmToken: nil),
                UserProfile(id: "friend_1_partner", displayName: "Sam", avatarId: "dog_4",
                            partnerCode: "ABC124", partnerId: "friend_1",
                            immunityUntil: nil, friendIds: [], createdAt: Date(), fcmToken: nil),
            ]),
        ]
    }
}

