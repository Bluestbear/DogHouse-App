//
//  Challenge.swift
//  DogHouse
//
//  Couple challenges: quizzes, photo dashes, and the anniversary race.
//  Winners earn a "Whatever I Want" card (wishCards on the user profile).
//

import Foundation

struct Challenge: Codable, Identifiable {
    var id: String
    var coupleKey: String
    var type: String              // "quiz" | "photo" | "anniversary"
    var title: String
    var prompt: String
    var createdBy: String
    var participants: [String]
    var status: String            // "active" | "completed"
    var createdAt: Date
    // Quiz fields
    var options: [String]? = nil
    /// uid -> {"own": choice, "guess": guess about partner}
    var answers: [String: [String: String]]? = nil
    // Photo dash: winner's compressed JPEG, base64
    var photoData: String? = nil
    // Resolution (set by client claim for photo/anniversary, server for quiz)
    var winnerId: String? = nil
    var completedAt: Date? = nil
    /// Set server-side once the wish card has been granted
    var cardAwarded: Bool? = nil
    // Game fields (type "game"). The whole doc is written by the
    // createGame / answerGame callables; the author's answer stays in a
    // private subdoc until the guess is in, then lands here.
    var kind: String? = nil
    var answerIndex: Int? = nil
    var guessIndex: Int? = nil
    /// Guess modes: the guess was right. likelyTo: both named the same person.
    var correct: Bool? = nil

    var isActive: Bool { status == "active" }
    var isGame: Bool { type == "game" }
    var gameKind: GameKind? { kind.flatMap(GameKind.init(rawValue:)) }

    func hasAnswered(_ userId: String) -> Bool {
        answers?[userId] != nil
    }
}

// MARK: - Games (Play tab)

enum GameKind: String, CaseIterable, Identifiable {
    case preference, ballKnowledge, twoTruths, likelyTo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preference: "Preference Quiz"
        case .ballKnowledge: "Ball Knowledge"
        case .twoTruths: "Two Truths & a Lie"
        case .likelyTo: "Who's More Likely To"
        }
    }

    var emoji: String {
        switch self {
        case .preference: "💭"
        case .ballKnowledge: "🏀"
        case .twoTruths: "🤥"
        case .likelyTo: "👉"
        }
    }

    var tagline: String {
        switch self {
        case .preference: "Pick yours, they guess it"
        case .ballKnowledge: "Your question, your answer"
        case .twoTruths: "Can they spot the lie?"
        case .likelyTo: "Point at the guilty one"
        }
    }

    /// likelyTo scores togetherness, not a winner.
    var isMatchMode: Bool { self == .likelyTo }
}

/// `gameStats/{coupleKey}` — written only by the answerGame callable.
struct GameStats: Equatable {
    var played = 0
    var wins: [String: Int] = [:]
    var likelyToPlayed = 0
    var inSync = 0
    /// Wins toward the next Whatever-I-Want card, 0...cardEvery.
    var cardProgress: [String: Int] = [:]

    static let cardEvery = 5

    init() {}

    init(_ data: [String: Any]) {
        played = data["played"] as? Int ?? 0
        wins = data["wins"] as? [String: Int] ?? [:]
        likelyToPlayed = data["likelyToPlayed"] as? Int ?? 0
        inSync = data["inSync"] as? Int ?? 0
        cardProgress = data["cardProgress"] as? [String: Int] ?? [:]
    }
}

/// `taskRenegotiation/{coupleKey}` — one partner asked to redo the task list.
struct TaskRenegotiation: Equatable {
    var requestedBy: String
    var requestedAt: Date?
    /// Both agreed: the negotiation is open until the new list is confirmed.
    var accepted = false
}

/// Bank prompts for Who's More Likely To.
enum LikelyToBank {
    static let prompts: [String] = [
        "...forget where they parked?",
        "...cry at a movie?",
        "...eat the last slice without asking?",
        "...get lost with GPS on?",
        "...start a fight over the thermostat?",
        "...fall asleep first on a movie night?",
        "...adopt a dog on a whim?",
        "...text back three days later?",
        "...plan a surprise trip?",
        "...burn toast?",
        "...talk to the dog like a person?",
        "...say sorry first?",
    ]
}

/// A redeemed "Whatever I Want" card
struct Wish: Codable, Identifiable {
    var id: String
    var fromUserId: String
    var toUserId: String
    var fromName: String
    var text: String
    var createdAt: Date
    var fulfilled: Bool? = nil
}

// MARK: - Quiz Question Bank

struct QuizQuestion {
    let prompt: String
    let optionA: String
    let optionB: String

    static let bank: [QuizQuestion] = [
        QuizQuestion(prompt: "What would your partner prefer for a vacation?", optionA: "Italy 🇮🇹", optionB: "Sweden 🇸🇪"),
        QuizQuestion(prompt: "Your partner's ideal Friday night?", optionA: "Cozy night in 🛋️", optionB: "Out with friends 🎉"),
        QuizQuestion(prompt: "What would your partner pick?", optionA: "Beach day 🏖️", optionB: "Mountain hike ⛰️"),
        QuizQuestion(prompt: "Your partner's dream pet (besides you)?", optionA: "Another dog 🐕", optionB: "A cat 🐈"),
        QuizQuestion(prompt: "What would your partner rather give up for a month?", optionA: "Coffee ☕", optionB: "Social media 📱"),
        QuizQuestion(prompt: "Your partner's breakfast pick?", optionA: "Sweet 🥞", optionB: "Savory 🍳"),
        QuizQuestion(prompt: "What movie night would your partner choose?", optionA: "Comedy 😂", optionB: "Thriller 😱"),
        QuizQuestion(prompt: "Your partner wins the lottery. First move?", optionA: "Save it 🏦", optionB: "Spend it 🛍️"),
        QuizQuestion(prompt: "What would your partner prefer?", optionA: "Fancy dinner out 🍽️", optionB: "Home-cooked together 👩‍🍳"),
        QuizQuestion(prompt: "Your partner's superpower of choice?", optionA: "Fly ✈️", optionB: "Read minds 🧠"),
        QuizQuestion(prompt: "How does your partner prefer to travel?", optionA: "Planned itinerary 🗓️", optionB: "Wing it 🎒"),
        QuizQuestion(prompt: "Your partner's karaoke energy?", optionA: "Grabs the mic 🎤", optionB: "Never. Ever. 🙅"),
        QuizQuestion(prompt: "What would your partner rather host?", optionA: "Game night 🎲", optionB: "Dinner party 🥂"),
        QuizQuestion(prompt: "Your partner's ideal morning?", optionA: "Sleep in 😴", optionB: "Early adventure 🌅"),
        QuizQuestion(prompt: "Which chore would your partner banish forever?", optionA: "Dishes 🍽️", optionB: "Laundry 🧺"),
    ]

    static func random() -> QuizQuestion {
        bank.randomElement()!
    }
}
