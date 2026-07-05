//
//  DoghouseEvent.swift
//  DogHouse
//

import Foundation

struct DoghouseEvent: Codable, Identifiable {
    var id: String
    var senderId: String
    var receiverId: String
    var reason: String
    var suggestion: String?
    var startedAt: Date
    var endedAt: Date?
    var isActive: Bool
    /// The dog says they completed the make-it-up suggestion
    var redemptionRequested: Bool? = nil
    /// nil/"sender" = partner released; "vote" = jailbreak vote; "redemption" = make-it-up confirmed
    var releasedBy: String? = nil

    /// Duration the user has been (or was) in the doghouse
    var duration: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }
}
