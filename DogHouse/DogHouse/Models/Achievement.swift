//
//  Achievement.swift
//  DogHouse
//
//  Couple achievements: badges the two of you earn together. They are
//  judged entirely on the client from data Home already holds (doghouse
//  history, room levels, challenges, profiles) plus two counters the app
//  bumps as roses and belly rubs go out. Unlocks are stored per couple in
//  achievements/{coupleKey} and never come back — a badge earned stays
//  earned even if the numbers later drop.
//

import Foundation

enum AchievementID: String, CaseIterable, Codable, Sendable {
    // The DogHouse
    case firstOffence, repeatOffender, quickForgiveness, hardTime, redemptionArc, bothGuilty, stormSurvivor
    // Keeping the peace
    case cleanWeek, cleanMonth, homeSweetHome, dogPalace
    // Play
    case quizNight, mindReaders, sayCheese, wishGranted
    // Affection
    case roseGarden, bellyRubChampion
    // Couple life
    case dressedUp, treatHoarder, doubleDate
}

enum AchievementCategory: String, CaseIterable, Sendable {
    case doghouse = "The DogHouse"
    case peace = "Keeping the Peace"
    case play = "Play"
    case affection = "Affection"
    case life = "Couple Life"
}

/// The two things nothing else records: how many roses and belly rubs the
/// couple has sent between them.
struct AchievementCounters: Codable, Equatable, Sendable {
    var roses = 0
    var bellyRubs = 0
}

/// Everything an achievement can be judged on. Home assembles it from the
/// services it already observes, so the rules below stay pure functions.
struct AchievementSnapshot {
    var userId: String
    var partnerId: String
    /// Ended history plus any active stays, both directions.
    var events: [DoghouseEvent]
    var now: Date
    /// How long BOTH dogs have been home — 0 while either is in.
    var bothHomeFor: TimeInterval
    var myLevel: RoomLevel
    var partnerLevel: RoomLevel
    var challenges: [Challenge]
    var maxWishCards: Int
    var dressedCount: Int
    var maxTreats: Int
    var friendCount: Int
    var counters: AchievementCounters

    /// Length of a stay as of `now` — an active stay measures up to the
    /// snapshot's clock, not the wall clock.
    func duration(of event: DoghouseEvent) -> TimeInterval {
        (event.endedAt ?? now).timeIntervalSince(event.startedAt)
    }
}

struct Achievement: Identifiable, Sendable {
    let id: AchievementID
    let category: AchievementCategory
    let emoji: String
    let title: String
    let description: String
    /// The number that has to be reached.
    let target: Int
    /// The unit shown next to progress ("stays", "days"); nil for one-offs.
    let unit: String?

    static let all: [Achievement] = [
        // The DogHouse
        Achievement(id: .firstOffence, category: .doghouse, emoji: "🐕", title: "First Offence",
                    description: "Someone got sent to the DogHouse for the first time.", target: 1, unit: nil),
        Achievement(id: .repeatOffender, category: .doghouse, emoji: "🔁", title: "Repeat Offender",
                    description: "Ten DogHouse stays between the two of you.", target: 10, unit: "stays"),
        Achievement(id: .quickForgiveness, category: .doghouse, emoji: "⏱️", title: "Quick Forgiveness",
                    description: "Let out again within an hour.", target: 1, unit: nil),
        Achievement(id: .hardTime, category: .doghouse, emoji: "🪨", title: "Hard Time",
                    description: "A stay that lasted a full day.", target: 1, unit: nil),
        Achievement(id: .redemptionArc, category: .doghouse, emoji: "🦴", title: "Redemption Arc",
                    description: "Made it up and got confirmed out.", target: 1, unit: nil),
        Achievement(id: .bothGuilty, category: .doghouse, emoji: "⚖️", title: "Both Guilty",
                    description: "Each of you has done time.", target: 2, unit: "of you"),
        Achievement(id: .stormSurvivor, category: .doghouse, emoji: "⛈️", title: "Storm Survivor",
                    description: "Sat through the storm — five days in.", target: 1, unit: nil),
        // Keeping the peace
        Achievement(id: .cleanWeek, category: .peace, emoji: "🕊️", title: "Clean Week",
                    description: "Seven days with nobody in the DogHouse.", target: 7, unit: "days"),
        Achievement(id: .cleanMonth, category: .peace, emoji: "🏆", title: "Clean Month",
                    description: "Thirty days with nobody in the DogHouse.", target: 30, unit: "days"),
        Achievement(id: .homeSweetHome, category: .peace, emoji: "🖼️", title: "Home Sweet Home",
                    description: "A living room reaches level 6.", target: 6, unit: "level"),
        Achievement(id: .dogPalace, category: .peace, emoji: "👑", title: "Dog Palace",
                    description: "A living room reaches level 10.", target: 10, unit: "level"),
        // Play
        Achievement(id: .quizNight, category: .play, emoji: "🧠", title: "Quiz Night",
                    description: "Finished your first couple quiz.", target: 1, unit: nil),
        Achievement(id: .mindReaders, category: .play, emoji: "🔮", title: "Mind Readers",
                    description: "Matched answers on five quizzes.", target: 5, unit: "matches"),
        Achievement(id: .sayCheese, category: .play, emoji: "📸", title: "Say Cheese",
                    description: "Won a Photo Dash.", target: 1, unit: nil),
        Achievement(id: .wishGranted, category: .play, emoji: "🎟️", title: "Wish Granted",
                    description: "Held a Whatever-I-Want card.", target: 1, unit: nil),
        // Affection
        Achievement(id: .roseGarden, category: .affection, emoji: "🌹", title: "Rose Garden",
                    description: "Ten bouquets sent between you.", target: 10, unit: "roses"),
        Achievement(id: .bellyRubChampion, category: .affection, emoji: "🐾", title: "Belly Rub Champion",
                    description: "Twenty-five belly rubs between you.", target: 25, unit: "rubs"),
        // Couple life
        Achievement(id: .dressedUp, category: .life, emoji: "🎩", title: "Dressed Up",
                    description: "Both dogs wearing something from the Shop.", target: 2, unit: "dogs"),
        Achievement(id: .treatHoarder, category: .life, emoji: "💰", title: "Treat Hoarder",
                    description: "One of you sitting on 500 treats.", target: 500, unit: "treats"),
        Achievement(id: .doubleDate, category: .life, emoji: "👯", title: "Double Date",
                    description: "Added another couple as friends.", target: 1, unit: nil)
    ]

    static func named(_ id: AchievementID) -> Achievement {
        all.first { $0.id == id }!
    }

    /// Where the couple stands right now, capped at the target.
    func progress(in s: AchievementSnapshot) -> Int {
        let raw: Int
        switch id {
        case .firstOffence, .repeatOffender:
            raw = s.events.count
        case .quickForgiveness:
            raw = s.events.filter { $0.endedAt != nil && s.duration(of: $0) < 3600 }.count
        case .hardTime:
            raw = s.events.filter { s.duration(of: $0) >= 86_400 }.count
        case .redemptionArc:
            raw = s.events.filter { $0.releasedBy == "redemption" }.count
        case .bothGuilty:
            raw = Set(s.events.map(\.receiverId)).intersection([s.userId, s.partnerId]).count
        case .stormSurvivor:
            raw = s.events.filter { s.duration(of: $0) >= 5 * 86_400 }.count
        case .cleanWeek, .cleanMonth:
            raw = Int(s.bothHomeFor / 86_400)
        case .homeSweetHome, .dogPalace:
            raw = max(s.myLevel.rawValue, s.partnerLevel.rawValue)
        case .quizNight:
            raw = s.challenges.filter { $0.type == "quiz" && $0.status == "completed" }.count
        case .mindReaders:
            raw = s.challenges.filter { $0.type == "quiz" && $0.status == "completed" && Self.answersMatch($0) }.count
        case .sayCheese:
            raw = s.challenges.filter { $0.type == "photo" && $0.status == "completed" && $0.winnerId != nil }.count
        case .wishGranted:
            raw = s.maxWishCards
        case .roseGarden:
            raw = s.counters.roses
        case .bellyRubChampion:
            raw = s.counters.bellyRubs
        case .dressedUp:
            raw = s.dressedCount
        case .treatHoarder:
            raw = s.maxTreats
        case .doubleDate:
            raw = s.friendCount
        }
        return min(max(raw, 0), target)
    }

    func isEarned(in s: AchievementSnapshot) -> Bool {
        progress(in: s) >= target
    }

    /// A quiz "matches" when both partners picked the same option.
    private static func answersMatch(_ challenge: Challenge) -> Bool {
        guard let answers = challenge.answers, answers.count == 2 else { return false }
        let own = answers.values.compactMap { $0["own"] }
        return own.count == 2 && own[0] == own[1]
    }
}
