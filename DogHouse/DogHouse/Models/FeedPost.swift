//
//  FeedPost.swift
//  DogHouse
//
//  A public doghouse sending, visible to the sender's friends.
//  Names and avatars are denormalized at creation so the feed
//  renders without extra profile fetches.
//

import Foundation

struct FeedPost: Codable, Identifiable, Equatable {
    var id: String
    var eventId: String
    var senderId: String
    var receiverId: String
    var senderName: String
    var receiverName: String
    var senderAvatarId: String?
    var receiverAvatarId: String?
    var reason: String
    var createdAt: Date
    var endedAt: Date?
    var status: String // "active" | "released"
    var audienceIds: [String]
    var reactions: [String: String]? // uid -> "back" | "dog"
    var voteEventId: String?
    var releasedByVote: Bool?

    var isActive: Bool { status == "active" }

    /// How many friends back the sending (❤️)
    var backCount: Int {
        (reactions ?? [:]).values.filter { $0 == FeedReaction.back.rawValue }.count
    }

    /// How many friends side with the dog (🐶)
    var dogCount: Int {
        (reactions ?? [:]).values.filter { $0 == FeedReaction.dog.rawValue }.count
    }

    func reaction(of userId: String) -> FeedReaction? {
        guard let raw = reactions?[userId] else { return nil }
        return FeedReaction(rawValue: raw)
    }

    /// Duration the dog spent (or has spent so far) in the doghouse
    var servedDuration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(createdAt)
    }
}

enum FeedReaction: String {
    case back // ❤️ supports the sender's call
    case dog  // 🐶 sides with the one in the doghouse

    var emoji: String {
        switch self {
        case .back: return "❤️"
        case .dog: return "🐶"
        }
    }
}
