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

    var isActive: Bool { status == "active" }
    var isTie: Bool { status == "completed" && winnerId == nil }

    func hasAnswered(_ userId: String) -> Bool {
        answers?[userId] != nil
    }
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

// MARK: - Photo Dash Prompts

enum PhotoDashPrompt {
    static let all = [
        "First to send a selfie wins! 🤳",
        "First to send a pic of what they're doing right now 📸",
        "First to send a photo of something that reminds them of us ❤️",
        "First to send their best silly face 🤪",
        "First to send a pic of the view from where they are 🪟",
    ]

    static func random() -> String {
        all.randomElement()!
    }
}
