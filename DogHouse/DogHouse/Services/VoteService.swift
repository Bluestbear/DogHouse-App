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
    private var jointVoteListener: ListenerRegistration?
    /// Results per group-chunk listener, merged into activeVoteEvents
    private var chunkResults: [Int: [VoteEvent]] = [:]
    private var jointVotes: [VoteEvent] = []

    init(userId: String) {
        // Resolve real user ID from Firebase Auth when views pass "mock_user"
        if userId == "mock_user", let realUid = Auth.auth().currentUser?.uid {
            self.userId = realUid
        } else {
            self.userId = userId
        }

        // SwiftUI Preview guard
        guard self.userId != "mock_user" else { return }

        // Joint doghouse votes target me via audienceIds, independent of groups
        jointVoteListener = fs.voteEventsCollection
            .whereField("audienceIds", arrayContains: self.userId)
            .whereField("status", isEqualTo: "active")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self, let docs = snapshot?.documents else { return }
                    self.jointVotes = docs.compactMap {
                        try? self.fs.decode(VoteEvent.self, from: $0)
                    }
                    self.mergeVotes()
                }
            }
    }

    deinit {
        listeners.forEach { $0.remove() }
        jointVoteListener?.remove()
    }

    /// Start listening for active votes in the given groups
    func listenForVotes(inGroupIds groupIds: [String]) {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        chunkResults.removeAll()

        guard !groupIds.isEmpty else {
            Task { @MainActor in self.mergeVotes() }
            return
        }

        // Firestore `in` supports up to 30
        for (index, chunk) in groupIds.chunked(into: 30).enumerated() {
            let listener = fs.voteEventsCollection
                .whereField("groupId", in: chunk)
                .whereField("status", isEqualTo: "active")
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self else { return }
                    Task { @MainActor [weak self] in
                        guard let self, let docs = snapshot?.documents else { return }
                        self.chunkResults[index] = docs.compactMap {
                            try? self.fs.decode(VoteEvent.self, from: $0)
                        }
                        self.mergeVotes()
                    }
                }
            listeners.append(listener)
        }
    }

    @MainActor
    private func mergeVotes() {
        var merged = chunkResults.values.flatMap { $0 } + jointVotes
        // De-duplicate (a joint vote could theoretically appear in both)
        var seen = Set<String>()
        merged = merged.filter { seen.insert($0.id).inserted }
        activeVoteEvents = merged
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
