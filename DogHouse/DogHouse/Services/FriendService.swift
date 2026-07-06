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

    private(set) var userId: String
    private var partnerId: String?
    private let fs = FirebaseService.shared
    private var linksListener: ListenerRegistration?
    private var profileCache: [String: UserProfile] = [:]

    private var myCoupleKey: String? {
        guard let partnerId, partnerId != "skipped" else { return nil }
        return fs.coupleKey(userId1: userId, userId2: partnerId)
    }

    init(userId: String) {
        // Resolve real user ID from Firebase Auth when views pass "mock_user"
        if userId == "mock_user", let realUid = Auth.auth().currentUser?.uid {
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

    deinit {
        linksListener?.remove()
    }

    private func resolvePartnerAndListen() async {
        guard let doc = try? await fs.usersCollection.document(userId).getDocument() else { return }
        let pid = doc.data()?["partnerId"] as? String
        await MainActor.run {
            self.partnerId = pid
            self.startListening()
        }
    }

    private func startListening() {
        linksListener = fs.db.collection("coupleFriendships")
            .whereField("memberIds", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self, let docs = snapshot?.documents else { return }
                    await self.rebuildCouples(from: docs)
                }
            }
    }

    @MainActor
    private func rebuildCouples(from docs: [QueryDocumentSnapshot]) async {
        guard let myKey = myCoupleKey else { return }
        var couples: [FriendCouple] = []
        for doc in docs {
            let keys = doc.data()["coupleKeys"] as? [String] ?? []
            guard let otherKey = keys.first(where: { $0 != myKey }) else { continue }
            let otherIds = otherKey.split(separator: "_").map(String.init)
            let profiles = (try? await fetchProfiles(for: otherIds)) ?? []
            guard !profiles.isEmpty else { continue }
            couples.append(FriendCouple(coupleKey: otherKey, members: profiles))
        }
        friendCouples = couples.sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Actions (server-validated)

    /// Link with another couple using either partner's code.
    func addCouple(code: String) async throws {
        try await CloudFunctions.shared.call("addCoupleFriend", ["code": code.uppercased()])
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
        for chunk in toFetch.chunked(into: 30) {
            let snapshot = try await fs.usersCollection
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            for doc in snapshot.documents {
                if let profile = try? fs.decode(UserProfile.self, from: doc) {
                    profileCache[profile.id] = profile
                    results.append(profile)
                }
            }
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

// MARK: - Array Chunking Helper

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
