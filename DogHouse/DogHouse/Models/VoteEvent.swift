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
    var status: String // "active" or "completed"
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
}
