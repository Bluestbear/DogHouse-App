//
//  AchievementTests.swift
//  DogHouseTests
//
//  Badges are judged from a snapshot; these pin the rules that are easy to
//  get subtly wrong (durations, both-guilty, quiz matches, clamping).
//

import Foundation
import Testing
@testable import DogHouse

struct AchievementTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(receiver: String, hours: Double, ended: Bool = true, releasedBy: String? = nil) -> DoghouseEvent {
        DoghouseEvent(
            id: UUID().uuidString, senderId: "x", receiverId: receiver, reason: "r", suggestion: nil,
            startedAt: now.addingTimeInterval(-hours * 3600),
            endedAt: ended ? now : nil, isActive: !ended, redemptionRequested: nil, releasedBy: releasedBy
        )
    }

    private func quiz(a: String, b: String) -> Challenge {
        Challenge(id: UUID().uuidString, coupleKey: "a_b", type: "quiz", title: "q", prompt: "p",
                  createdBy: "a", participants: ["a", "b"], status: "completed", createdAt: now,
                  options: ["1", "2"], answers: ["a": ["own": a], "b": ["own": b]])
    }

    private func snapshot(events: [DoghouseEvent] = [], challenges: [Challenge] = [],
                          bothHomeFor: TimeInterval = 0, counters: AchievementCounters = .init()) -> AchievementSnapshot {
        AchievementSnapshot(
            userId: "a", partnerId: "b", events: events, now: now, bothHomeFor: bothHomeFor,
            myLevel: .bareBones, partnerLevel: .bareBones, challenges: challenges,
            maxWishCards: 0, dressedCount: 0, maxTreats: 0, friendCount: 0, counters: counters
        )
    }

    @Test("Every id has exactly one definition")
    func definitions() {
        #expect(Achievement.all.count == AchievementID.allCases.count)
        #expect(Set(Achievement.all.map(\.id)).count == AchievementID.allCases.count)
    }

    @Test("Stay-based badges read durations and releases")
    func stays() {
        let s = snapshot(events: [
            event(receiver: "a", hours: 0.5),
            event(receiver: "a", hours: 30, releasedBy: "redemption"),
            event(receiver: "b", hours: 130, ended: false)
        ])
        #expect(Achievement.named(.firstOffence).isEarned(in: s))
        #expect(Achievement.named(.quickForgiveness).isEarned(in: s))
        #expect(Achievement.named(.hardTime).isEarned(in: s))
        #expect(Achievement.named(.redemptionArc).isEarned(in: s))
        #expect(Achievement.named(.bothGuilty).isEarned(in: s))
        #expect(Achievement.named(.stormSurvivor).isEarned(in: s))
        #expect(Achievement.named(.repeatOffender).progress(in: s) == 3)
    }

    @Test("An active stay is not 'quick forgiveness' yet")
    func activeStayIsNotQuick() {
        let s = snapshot(events: [event(receiver: "a", hours: 0.2, ended: false)])
        #expect(!Achievement.named(.quickForgiveness).isEarned(in: s))
    }

    @Test("Quizzes count only when both picked the same option")
    func quizMatches() {
        let s = snapshot(challenges: [quiz(a: "1", b: "1"), quiz(a: "1", b: "2"), quiz(a: "2", b: "2")])
        #expect(Achievement.named(.quizNight).isEarned(in: s))
        #expect(Achievement.named(.mindReaders).progress(in: s) == 2)
    }

    private func game(_ kind: GameKind, correct: Bool, status: String = "completed") -> Challenge {
        Challenge(id: UUID().uuidString, coupleKey: "a_b", type: "game", title: kind.title, prompt: "...burn toast?",
                  createdBy: "b", participants: ["a", "b"], status: status, createdAt: now,
                  options: ["me", "you"], kind: kind.rawValue, correct: correct)
    }

    @Test("Play games count toward the quiz badges; right guesses and in-sync answers are matches")
    func gameMatches() {
        let s = snapshot(challenges: [
            game(.preference, correct: true),
            game(.likelyTo, correct: true),
            game(.twoTruths, correct: false),
            game(.ballKnowledge, correct: true, status: "active"),
            quiz(a: "1", b: "1"),
        ])
        #expect(Achievement.named(.quizNight).isEarned(in: s))
        #expect(Achievement.named(.mindReaders).progress(in: s) == 3)
    }

    @Test("likelyTo reads from the viewer's side")
    func likelyToLabels() {
        let g = game(.likelyTo, correct: false, status: "active")
        #expect(g.displayPrompt == "Who's more likely to burn toast?")
        #expect(g.optionLabels(viewerIsAuthor: false, authorName: "Bea", guesserName: "Al") == ["Me", "Bea"])
        #expect(g.optionLabels(viewerIsAuthor: true, authorName: "Bea", guesserName: "Al") == ["Me", "Al"])
    }

    @Test("Peace badges count whole days both at home, capped at the target")
    func peace() {
        let s = snapshot(bothHomeFor: 45 * 86_400)
        #expect(Achievement.named(.cleanWeek).isEarned(in: s))
        #expect(Achievement.named(.cleanMonth).progress(in: s) == 30)
    }

    @Test("Counters drive the affection badges")
    func counters() {
        let s = snapshot(counters: AchievementCounters(roses: 10, bellyRubs: 3))
        #expect(Achievement.named(.roseGarden).isEarned(in: s))
        #expect(Achievement.named(.bellyRubChampion).progress(in: s) == 3)
    }
}
