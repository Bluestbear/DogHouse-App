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
    private var listeners: [ListenerRegistration] = []

    init(userId: String) {
        // Resolve real user ID from Firebase Auth when views pass "mock_user"
        if userId == "mock_user", let realUid = Auth.auth().currentUser?.uid {
            self.userId = realUid
        } else {
            self.userId = userId
        }
    }

    deinit {
        listeners.forEach { $0.remove() }
    }

    /// Start listening for active votes in the given groups
    func listenForVotes(inGroupIds groupIds: [String]) {
        listeners.forEach { $0.remove() }
        listeners.removeAll()

        guard !groupIds.isEmpty else { return }

        // Firestore `in` supports up to 30
        for chunk in groupIds.chunked(into: 30) {
            let listener = fs.voteEventsCollection
                .whereField("groupId", in: chunk)
                .whereField("status", isEqualTo: "active")
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self else { return }
                    Task { @MainActor [weak self] in
                        guard let self, let docs = snapshot?.documents else { return }
                        let events = docs.compactMap {
                            try? self.fs.decode(VoteEvent.self, from: $0)
                        }
                        self.activeVoteEvents = events
                    }
                }
            listeners.append(listener)
        }
    }

    // MARK: - Actions

    func castVote(voteEventId: String, votedForUserId: String) async throws {
        try await fs.voteEventsCollection.document(voteEventId).updateData([
            "votes.\(userId)": votedForUserId
        ])
        // Listener updates activeVoteEvents automatically
    }

    func createVoteEvent(groupId: String, doghousedUserIds: [String], durationMinutes: Int = 30) async throws {
        let docRef = fs.voteEventsCollection.document()
        let event = VoteEvent(
            id: docRef.documentID,
            groupId: groupId,
            doghousedUserIds: doghousedUserIds,
            votes: [:],
            startedAt: Date(),
            endsAt: Date().addingTimeInterval(Double(durationMinutes) * 60),
            winnerId: nil,
            status: "active"
        )
        try await docRef.setData(fs.encoder.encode(event))
    }

    func resolveVoteEvent(voteEventId: String) async throws {
        guard let event = activeVoteEvents.first(where: { $0.id == voteEventId }),
              event.status == "active" else { return }

        var voteCounts: [String: Int] = [:]
        for votedForId in event.votes.values {
            voteCounts[votedForId, default: 0] += 1
        }
        let winnerId = voteCounts.max(by: { $0.value < $1.value })?.key

        var updateData: [String: Any] = ["status": "completed"]
        if let winnerId { updateData["winnerId"] = winnerId }
        try await fs.voteEventsCollection.document(voteEventId).updateData(updateData)
    }

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
