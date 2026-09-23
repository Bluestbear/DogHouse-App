//
//  FeedService.swift
//  DogHouse
//
//  Real-time friends feed: public doghouse sendings shared with me,
//  plus reaction toggling. Mock data preserved for SwiftUI Previews.
//

import SwiftUI
import Combine
import OSLog
import FirebaseAuth
import FirebaseFirestore

class FeedService: ObservableObject {
    @Published var posts: [FeedPost] = []

    private(set) var userId: String
    private let fs = FirebaseService.shared
    private var feedListener: ListenerRegistration?

    /// Posts older than this stop showing in the feed
    static let feedWindow: TimeInterval = 7 * 24 * 3600

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

        startListening()
    }

    isolated deinit {
        feedListener?.remove()
    }

    private func startListening() {
        // Equality-only query (no orderBy) so no composite index is needed;
        // sorting and the 7-day window are applied client-side.
        feedListener = fs.feedPostsCollection
            .whereField("audienceIds", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        Logger.data.error("Feed listener failed: \(error.localizedDescription, privacy: .public)")
                        return
                    }
                    guard let docs = snapshot?.documents else { return }
                    let cutoff = Date().addingTimeInterval(-Self.feedWindow)
                    self.posts = docs
                        .compactMap { try? self.fs.decode(FeedPost.self, from: $0) }
                        .filter { $0.createdAt > cutoff }
                        .sorted { $0.createdAt > $1.createdAt }
                }
            }
    }

    // MARK: - Reactions

    /// Toggle my reaction on a post: tapping the current reaction removes it,
    /// tapping the other switches it.
    func react(to post: FeedPost, with reaction: FeedReaction) async throws {
        guard userId != "mock_user" else { return }
        let current = post.reaction(of: userId)
        let value: Any = (current == reaction) ? FieldValue.delete() : reaction.rawValue
        try await fs.feedPostsCollection.document(post.id).updateData([
            "reactions.\(userId)": value
        ])
    }

    /// Set or replace my roast on a post; nil clears it
    func roast(_ post: FeedPost, with text: String?) async throws {
        guard userId != "mock_user" else { return }
        let value: Any = text ?? FieldValue.delete()
        try await fs.feedPostsCollection.document(post.id).updateData([
            "roasts.\(userId)": value
        ])
    }

    // MARK: - Mock Data (Preview only)

    private func loadMockData() {
        posts = [
            FeedPost(
                id: "post_1", eventId: "event_1",
                senderId: "friend_1", receiverId: "friend_1_partner",
                senderName: "Jordan", receiverName: "Sam",
                senderAvatarId: "dog_3", receiverAvatarId: "dog_4",
                reason: "Left the milk out ALL day",
                createdAt: Date().addingTimeInterval(-3600), endedAt: nil,
                status: "active", audienceIds: [userId],
                reactions: ["x": "back", "y": "back", "z": "dog"],
                voteEventId: nil, releasedByVote: nil
            ),
            FeedPost(
                id: "post_2", eventId: "event_2",
                senderId: "friend_2", receiverId: "friend_2_partner",
                senderName: "Riley", receiverName: "Alex",
                senderAvatarId: "dog_5", receiverAvatarId: "dog_1",
                reason: "Forgot our anniversary dinner",
                createdAt: Date().addingTimeInterval(-86400), endedAt: Date().addingTimeInterval(-80000),
                status: "released", audienceIds: [userId],
                reactions: ["x": "dog"],
                voteEventId: nil, releasedByVote: true
            ),
        ]
    }
}
