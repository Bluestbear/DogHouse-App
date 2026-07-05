//
//  FriendService.swift
//  DogHouse
//
//  Firestore-backed friend service with real-time listeners for
//  pending requests and groups. Mock data preserved for SwiftUI Previews.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

class FriendService: ObservableObject {
    @Published var friends: [UserProfile] = []
    @Published var pendingRequests: [Friendship] = []
    @Published var groups: [FriendGroup] = []

    private var userId: String
    private let fs = FirebaseService.shared
    private var pendingListener: ListenerRegistration?
    private var groupsListener: ListenerRegistration?

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

        startListening()
        Task { await fetchFriends() }
    }

    deinit {
        pendingListener?.remove()
        groupsListener?.remove()
    }

    // MARK: - Listeners

    private func startListening() {
        // Listen for incoming pending friend requests
        pendingListener = fs.friendshipsCollection
            .whereField("toUserId", isEqualTo: userId)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self, let docs = snapshot?.documents else { return }
                    self.pendingRequests = docs.compactMap {
                        try? self.fs.decode(Friendship.self, from: $0)
                    }
                }
            }

        // Listen for groups the user is a member of
        groupsListener = fs.friendGroupsCollection
            .whereField("memberIds", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self, let docs = snapshot?.documents else { return }
                    self.groups = docs.compactMap {
                        try? self.fs.decode(FriendGroup.self, from: $0)
                    }
                }
            }
    }

    /// Fetch full UserProfile for each friend ID
    private func fetchFriends() async {
        do {
            let userDoc = try await fs.usersCollection.document(userId).getDocument()
            guard let friendIds = userDoc.data()?["friendIds"] as? [String], !friendIds.isEmpty else { return }

            // Firestore `in` queries support up to 30 values per chunk
            var allProfiles: [UserProfile] = []
            for chunk in friendIds.chunked(into: 30) {
                let snapshot = try await fs.usersCollection
                    .whereField(FieldPath.documentID(), in: chunk)
                    .getDocuments()
                let profiles = snapshot.documents.compactMap {
                    try? fs.decode(UserProfile.self, from: $0)
                }
                allProfiles.append(contentsOf: profiles)
            }

            await MainActor.run {
                self.friends = allProfiles
            }
        } catch {
            print("Failed to fetch friends: \(error)")
        }
    }

    // MARK: - Friend Actions

    func sendFriendRequest(toCode: String) async throws {
        // Look up user by partner code
        let codeDoc = try await fs.partnerCodesCollection.document(toCode.uppercased()).getDocument()
        guard let targetUserId = codeDoc.data()?["userId"] as? String else {
            throw NSError(domain: "FriendService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No user found with that code"])
        }

        guard targetUserId != userId else {
            throw NSError(domain: "FriendService", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "You cannot add yourself"])
        }

        let docRef = fs.friendshipsCollection.document()
        let friendship = Friendship(
            id: docRef.documentID,
            fromUserId: userId,
            toUserId: targetUserId,
            status: "pending",
            createdAt: Date()
        )

        try await docRef.setData(fs.encoder.encode(friendship))
    }

    func acceptFriendRequest(friendshipId: String) async throws {
        let ref = fs.friendshipsCollection.document(friendshipId)
        let doc = try await ref.getDocument()
        guard let fromUserId = doc.data()?["fromUserId"] as? String else { return }

        // Atomically: update status + add to both users' friendIds
        let batch = fs.db.batch()
        batch.updateData(["status": "accepted"], forDocument: ref)
        batch.updateData(["friendIds": FieldValue.arrayUnion([fromUserId])],
                         forDocument: fs.usersCollection.document(userId))
        batch.updateData(["friendIds": FieldValue.arrayUnion([userId])],
                         forDocument: fs.usersCollection.document(fromUserId))
        try await batch.commit()

        // Refresh friends list
        await fetchFriends()
    }

    func rejectFriendRequest(friendshipId: String) async throws {
        try await fs.friendshipsCollection.document(friendshipId).updateData(["status": "rejected"])
        // Listener will remove it from pendingRequests
    }

    func removeFriend(userId friendId: String) async throws {
        let batch = fs.db.batch()
        batch.updateData(["friendIds": FieldValue.arrayRemove([friendId])],
                         forDocument: fs.usersCollection.document(userId))
        batch.updateData(["friendIds": FieldValue.arrayRemove([userId])],
                         forDocument: fs.usersCollection.document(friendId))
        try await batch.commit()

        await MainActor.run {
            friends.removeAll { $0.id == friendId }
        }
    }

    func fetchProfiles(for userIds: [String]) async throws -> [UserProfile] {
        // In preview mode, return matching mock friends
        if userId == "mock_user" {
            return friends.filter { userIds.contains($0.id) }
        }
        guard !userIds.isEmpty else { return [] }
        var allProfiles: [UserProfile] = []
        for chunk in userIds.chunked(into: 30) {
            let snapshot = try await fs.usersCollection
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            let profiles = snapshot.documents.compactMap {
                try? fs.decode(UserProfile.self, from: $0)
            }
            allProfiles.append(contentsOf: profiles)
        }
        return allProfiles
    }

    func createGroup(name: String, memberIds: [String]) async throws {
        let docRef = fs.friendGroupsCollection.document()
        let group = FriendGroup(
            id: docRef.documentID,
            name: name,
            createdBy: userId,
            memberIds: [userId] + memberIds,
            createdAt: Date()
        )
        try await docRef.setData(fs.encoder.encode(group))
        // Listener will add it to groups
    }

    // MARK: - Mock Data (Preview only)

    private func loadMockData() {
        friends = [
            UserProfile(id: "friend_1", displayName: "Jordan", avatarId: "dog_3",
                        partnerCode: "ABC123", partnerId: "friend_1_partner",
                        immunityUntil: nil, friendIds: [],
                        createdAt: Date().addingTimeInterval(-86400 * 30), fcmToken: nil),
            UserProfile(id: "friend_2", displayName: "Riley", avatarId: "dog_5",
                        partnerCode: "XYZ789", partnerId: "friend_2_partner",
                        immunityUntil: nil, friendIds: [],
                        createdAt: Date().addingTimeInterval(-86400 * 14), fcmToken: nil),
        ]
        pendingRequests = [
            Friendship(id: "req_1", fromUserId: "stranger_1", toUserId: userId,
                       status: "pending", createdAt: Date().addingTimeInterval(-3600)),
        ]
        groups = [
            FriendGroup(id: "group_1", name: "The Squad", createdBy: userId,
                        memberIds: [userId, "friend_1", "friend_2"],
                        createdAt: Date().addingTimeInterval(-86400 * 7)),
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
