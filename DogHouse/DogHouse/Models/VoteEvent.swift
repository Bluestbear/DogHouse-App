//
//  VoteEvent.swift
//  DogHouse
//

import Foundation

struct VoteEvent: Codable, Identifiable {
    var id: String
    /// Set for legacy squad votes started from a friend group; nil for joint votes
    var groupId: String?
    /// "group" (default) or "joint_doghouse" (two friends doghoused at once)
    var type: String? = nil
    var doghousedUserIds: [String]
    /// Denormalized names for joint votes (uid -> displayName)
    var doghousedUserNames: [String: String]? = nil
    var votes: [String: String] // voterId -> votedForId
    var startedAt: Date
    var endsAt: Date
    var winnerId: String?
    /// Every dog the resolver actually freed (two on a tie; empty if nobody)
    var winnerIds: [String]? = nil
    var status: String // "active", "completed" or "cancelled"
    /// Set when a vote was called off because this dog was let out early
    var releasedUserId: String? = nil
    /// Everyone who can see/vote in a joint vote (both couples + their friends)
    var audienceIds: [String]? = nil
    /// The feed posts that triggered a joint vote
    var feedPostIds: [String]? = nil

    var isActive: Bool {
        status == "active"
    }

    var isJointVote: Bool {
        type == "joint_doghouse"
    }

    var isCancelled: Bool {
        status == "cancelled"
    }

    /// Who went free. `winnerIds` is authoritative once the server has
    /// resolved; older documents only carry `winnerId`.
    var freedUserIds: [String] {
        if let winnerIds { return winnerIds }
        return winnerId.map { [$0] } ?? []
    }

    /// Votes per candidate — only votes naming a dog in this vote count
    var tally: [String: Int] {
        var counts: [String: Int] = [:]
        for votedFor in votes.values where doghousedUserIds.contains(votedFor) {
            counts[votedFor, default: 0] += 1
        }
        return counts
    }
}
