//
//  FriendGroup.swift
//  DogHouse
//

import Foundation

struct FriendGroup: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var createdBy: String
    var memberIds: [String]
    var createdAt: Date
}
