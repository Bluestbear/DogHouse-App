//
//  DoghouseStats.swift
//  DogHouse
//
//  Streaks and totals computed from doghouse event history.
//

import Foundation

struct DoghouseStats {
    let timesInDoghouse: Int
    let timesSentPartner: Int
    let totalTimeServed: TimeInterval
    let currentCleanStreak: TimeInterval
    let longestCleanStreak: TimeInterval
    let timesSavedByVote: Int
    let timesRedeemed: Int

    /// - Parameters:
    ///   - history: completed doghouse events (any order)
    ///   - userId: the user whose stats to compute
    ///   - accountCreatedAt: start of the very first clean streak
    init(history: [DoghouseEvent], userId: String, accountCreatedAt: Date?) {
        let received = history
            .filter { $0.receiverId == userId }
            .sorted { $0.startedAt < $1.startedAt } // oldest first

        timesInDoghouse = received.count
        timesSentPartner = history.filter { $0.senderId == userId }.count
        totalTimeServed = received.reduce(0) { $0 + $1.duration }
        timesSavedByVote = received.filter { $0.releasedBy == "vote" }.count
        timesRedeemed = received.filter { $0.releasedBy == "redemption" }.count

        // Clean streaks = gaps between consecutive stints (plus the streak
        // before the first stint and the ongoing one since the last release)
        var streaks: [TimeInterval] = []
        var previousEnd = accountCreatedAt
        for event in received {
            if let start = previousEnd {
                streaks.append(max(event.startedAt.timeIntervalSince(start), 0))
            }
            previousEnd = event.endedAt ?? event.startedAt
        }
        let ongoing = previousEnd.map { max(Date().timeIntervalSince($0), 0) }
            ?? Date().timeIntervalSince(accountCreatedAt ?? Date())

        currentCleanStreak = ongoing
        longestCleanStreak = max(streaks.max() ?? 0, ongoing)
    }
}
