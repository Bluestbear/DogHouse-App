//
//  VoteEvent.swift
//  DogHouse
//

import Foundation

struct VoteEvent: Codable, Identifiable {
    var id: String
    var groupId: String
    var doghousedUserIds: [String]
    var votes: [String: String] // voterId -> votedForId
    var startedAt: Date
    var endsAt: Date
    var winnerId: String?
    var status: String // "active" or "completed"

    var isActive: Bool {
        status == "active"
    }
}
