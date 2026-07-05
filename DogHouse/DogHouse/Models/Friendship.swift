//
//  Friendship.swift
//  DogHouse
//

import Foundation

struct Friendship: Codable, Identifiable {
    var id: String
    var fromUserId: String
    var toUserId: String
    var status: String // "pending", "accepted", "rejected"
    var createdAt: Date

    var isPending: Bool { status == "pending" }
    var isAccepted: Bool { status == "accepted" }
}
