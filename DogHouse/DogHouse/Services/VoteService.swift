//
//  VoteService.swift
//  DogHouse
//
//  Firestore-backed vote service with real-time listeners for active vote events.
//

import SwiftUI
import Combine
import OSLog
import FirebaseAuth
import FirebaseFirestore

class VoteService: ObservableObject {
    @Published var activeVoteEvents: [VoteEvent] = []

    private(set) var userId: String
    private let fs = FirebaseService.shared
    private var voteListener: ListenerRegistration?

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

        // SwiftUI Preview guard
        guard self.userId != "mock_user" else {
            #if DEBUG
            // `-demoFriends` shows the jailbreak banner above the mock feed.
            if AuthService.isDemoFriends {
                activeVoteEvents = [VoteEvent(
                    id: "demo_vote", type: "joint_doghouse",
                    doghousedUserIds: ["friend_1_partner", "friend_2_partner"],
                    doghousedUserNames: ["friend_1_partner": "Sam", "friend_2_partner": "Luke"],
                    votes: [:], startedAt: Date(), endsAt: Date().addingTimeInterval(30 * 60),
                    status: "active"
                )]
            }
            #endif
            return
        }

        // One listener covers both joint and group votes: every vote carries
        // audienceIds, and querying by array-contains(me) is the shape the
        // security rules can prove (a groupId-in query gets denied).
        voteListener = fs.voteEventsCollection
            .whereField("audienceIds", arrayContains: self.userId)
            .whereField("status", isEqualTo: "active")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // A denied query (rule/query shape mismatch, missing index)
                    // fails silently otherwise — no banner, no error, no vote.
                    if let error {
                        Logger.data.error("Vote listener failed: \(error.localizedDescription, privacy: .public)")
                        return
                    }
                    guard let docs = snapshot?.documents else { return }
                    self.activeVoteEvents = docs.compactMap {
                        try? self.fs.decode(VoteEvent.self, from: $0)
                    }
                }
            }
    }

    isolated deinit {
        voteListener?.remove()
    }

    /// Wait for the server to settle a vote and return the final document.
    ///
    /// `resolveExpiredVotes` runs once a minute and a release by the dog's
    /// partner cancels a vote at any time, so the outcome can arrive up to a
    /// minute after the countdown — or well before it. Returns nil only when
    /// the wait is cancelled (the screen went away).
    func awaitResult(voteId: String) async -> VoteEvent? {
        guard userId != "mock_user" else { return nil }
        let ref = fs.voteEventsCollection.document(voteId)
        let updates = AsyncStream<VoteEvent> { continuation in
            // Only ever touched to remove the listener; Firestore's
            // registration type predates Sendable.
            nonisolated(unsafe) let registration = ref.addSnapshotListener { snapshot, error in
                Task { @MainActor in
                    if let error {
                        Logger.data.error("Vote result listener failed: \(error.localizedDescription, privacy: .public)")
                        return
                    }
                    guard let snapshot, snapshot.exists,
                          let event = try? FirebaseService.shared.decode(VoteEvent.self, from: snapshot)
                    else { return }
                    continuation.yield(event)
                }
            }
            continuation.onTermination = { _ in registration.remove() }
        }
        for await event in updates where !event.isActive {
            return event
        }
        return nil
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
