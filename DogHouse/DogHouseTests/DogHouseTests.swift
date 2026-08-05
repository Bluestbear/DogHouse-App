//
//  DogHouseTests.swift
//  DogHouseTests
//
//  Created by Harrison Krampe on 21.03.26.
//

import Foundation
import Testing
@testable import DogHouse

// MARK: - Home Timer Baseline

/// The "You've been home for" counter is driven by `homeStartDate`. It used to
/// fall back to a flat 3600 seconds, which pinned the timer at "1h 0m 0s" for
/// anyone with no doghouse history.
struct HomeStartDateTests {

    private let me = "user_me"
    private let them = "user_them"
    private let signup = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(
        receiver: String,
        started: Date,
        ended: Date?
    ) -> DoghouseEvent {
        DoghouseEvent(
            id: UUID().uuidString,
            senderId: receiver == me ? them : me,
            receiverId: receiver,
            reason: "test",
            suggestion: nil,
            startedAt: started,
            endedAt: ended,
            isActive: ended == nil
        )
    }

    @Test("No history falls back to the account creation date, not a flat hour")
    func noHistoryUsesAccountCreation() {
        let start = DoghouseService.homeStartDate(
            history: [],
            receiverId: me,
            accountCreatedAt: signup
        )
        #expect(start == signup)
    }

    @Test("A user with no history sees a counter that keeps growing")
    func noHistoryCounterAdvances() {
        let now = signup.addingTimeInterval(9 * 3600)
        let start = DoghouseService.homeStartDate(
            history: [],
            receiverId: me,
            accountCreatedAt: signup
        )
        #expect(now.timeIntervalSince(start!) == 9 * 3600)
        // The old behaviour returned exactly 3600 here, forever.
        #expect(now.timeIntervalSince(start!) != 3600)
    }

    @Test("The most recent release wins, regardless of list order")
    func usesMostRecentRelease() {
        let older = signup.addingTimeInterval(3600)
        let newer = signup.addingTimeInterval(86_400)
        let history = [
            event(receiver: me, started: signup, ended: older),
            event(receiver: me, started: signup, ended: newer)
        ]
        #expect(DoghouseService.homeStartDate(
            history: history, receiverId: me, accountCreatedAt: signup
        ) == newer)

        #expect(DoghouseService.homeStartDate(
            history: history.reversed(), receiverId: me, accountCreatedAt: signup
        ) == newer)
    }

    @Test("Events the user did not receive are ignored")
    func ignoresOtherPeoplesEvents() {
        let theirRelease = signup.addingTimeInterval(50_000)
        let history = [event(receiver: them, started: signup, ended: theirRelease)]
        #expect(DoghouseService.homeStartDate(
            history: history, receiverId: me, accountCreatedAt: signup
        ) == signup)
        #expect(DoghouseService.homeStartDate(
            history: history, receiverId: them, accountCreatedAt: nil
        ) == theirRelease)
    }

    @Test("An unfinished stint has no end date and cannot start the home clock")
    func ignoresActiveEvents() {
        let history = [event(receiver: me, started: signup, ended: nil)]
        #expect(DoghouseService.homeStartDate(
            history: history, receiverId: me, accountCreatedAt: signup
        ) == signup)
    }

    @Test("Nothing to anchor to yields no start date")
    func noBaselineAtAll() {
        #expect(DoghouseService.homeStartDate(
            history: [], receiverId: me, accountCreatedAt: nil
        ) == nil)
    }
}

// MARK: - Room Progression

struct RoomLevelTests {

    @Test("Levels track the elapsed time thresholds")
    func levelForDuration() {
        #expect(RoomLevel.level(for: 0) == .bareBones)
        #expect(RoomLevel.level(for: 3599) == .bareBones)
        #expect(RoomLevel.level(for: 3600) == .basicChair)
        #expect(RoomLevel.level(for: 86_400) == .pillowAndRug)
        #expect(RoomLevel.level(for: 10 * 86_400 * 365) == .palace)
    }

    @Test("A fresh account starts at the bottom of the ladder")
    func freshAccountStartsAtLevelOne() {
        // The old flat 3600 fallback handed every new user level 2 on sign-up.
        #expect(RoomLevel.level(for: 0) == .bareBones)
    }
}
