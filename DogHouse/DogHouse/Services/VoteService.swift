//
//  VoteService.swift
//  DogHouse
//
//  Firestore-backed vote service with real-time listeners for active vote events.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

class VoteService: ObservableObject {
    @Published var activeVoteEvents: [VoteEvent] = []

    private var userId: String
    private let fs = FirebaseService.shared
    private var voteListener: ListenerRegistration?

    init(userId: String) {
        // Resolve real user ID from Firebase Auth when views pass "mock_user"
        if userId == "mock_user", let realUid = Auth.auth().currentUser?.uid {
            self.userId = realUid
        } else {
            self.userId = userId
        }

        // SwiftUI Preview guard
        guard self.userId != "mock_user" else { return }

        // One listener covers both joint and group votes: every vote carries
        // audienceIds, and querying by array-contains(me) is the shape the
        // security rules can prove (a groupId-in query gets denied).
        voteListener = fs.voteEventsCollection
            .whereField("audienceIds", arrayContains: self.userId)
            .whereField("status", isEqualTo: "active")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self, let docs = snapshot?.documents else { return }
                    self.activeVoteEvents = docs.compactMap {
                        try? self.fs.decode(VoteEvent.self, from: $0)
                    }
                }
            }
    }

    isolated deinit {
        voteListener?.remove()
    }

    /// Active joint (two-friends-in-the-doghouse) votes I can participate in
    var activeJointVotes: [VoteEvent] {
        activeVoteEvents.filter { $0.isJointVote }
    }

    // MARK: - Actions

    func castVote(voteEventId: String, votedForUserId: String) async throws {
        try await fs.voteEventsCollection.document(voteEventId).updateData([
            "votes.\(userId)": votedForUserId
        ])
        // Listener updates activeVoteEvents automatically
    }


    // Vote resolution happens server-side (resolveExpiredVotes Cloud Function,
    // runs every minute): it tallies, releases the winner from the doghouse,
    // and notifies everyone. Clients only cast votes.

    func activeVoteEvent(forGroupId groupId: String) -> VoteEvent? {
        activeVoteEvents.first { $0.groupId == groupId }
    }

    func hasVoted(in voteEventId: String) -> Bool {
        guard let event = activeVoteEvents.first(where: { $0.id == voteEventId }) else {
            return false
        }
        return event.votes[userId] != nil
    }

    func votesFor(userId targetId: String, in voteEventId: String) -> Int {
        guard let event = activeVoteEvents.first(where: { $0.id == voteEventId }) else {
            return 0
        }
        return event.votes.values.filter { $0 == targetId }.count
    }

    func totalVotes(in voteEventId: String) -> Int {
        guard let event = activeVoteEvents.first(where: { $0.id == voteEventId }) else {
            return 0
        }
        return event.votes.count
    }
}
