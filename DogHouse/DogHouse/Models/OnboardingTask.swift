//
//  OnboardingTask.swift
//  DogHouse
//
//  Data models for the collaborative task negotiation onboarding flow.
//

import Foundation

// MARK: - Individual Task

struct OnboardingTask: Codable, Identifiable, Equatable {
    var id: String
    var title: String
}

// MARK: - Task Strike (a review action)

struct TaskStrike: Codable, Equatable {
    var originalTaskId: String
    var replacementTitle: String
}

// MARK: - Couple Task (final persisted task for gameplay)

struct CoupleTask: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var suggestedBy: String      // userId or "app"
    var isAppSuggestion: Bool
}

// MARK: - Onboarding Tasks Document (mirrors Firestore "onboardingTasks/{coupleKey}")

struct OnboardingTasksDocument: Codable, Identifiable {
    var id: String  // coupleKey

    var coupleId: String
    var user1Id: String
    var user1Tasks: [OnboardingTask]
    var user1Submitted: Bool
    var user2Id: String
    var user2Tasks: [OnboardingTask]
    var user2Submitted: Bool

    var user1Strikes: [TaskStrike]
    var user1ReviewComplete: Bool
    var user2Strikes: [TaskStrike]
    var user2ReviewComplete: Bool

    var user1Confirmed: Bool
    var user2Confirmed: Bool

    var finalTasks: [CoupleTask]

    // MARK: - Decoding

    enum CodingKeys: String, CodingKey {
        case id, coupleId
        case user1Id, user1Tasks, user1Submitted, user1Strikes, user1ReviewComplete, user1Confirmed
        case user2Id, user2Tasks, user2Submitted, user2Strikes, user2ReviewComplete, user2Confirmed
        case finalTasks
    }

    /// Decodes a half-written document.
    ///
    /// Each partner's writes touch only their own `userN*` fields (see
    /// `OnboardingService.submitMyTasks`), so between the first partner's
    /// submission and the second's, every field of the other half is legitimately
    /// absent. The synthesized initializer threw on those documents; the throw was
    /// logged and swallowed, `taskDocument` stayed nil, and the client fell back to
    /// the "no document yet" path — which is what made a partial document look
    /// identical to no document at all.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // The document id IS the sorted uid pair, so it can stand in for the
        // id fields if a write hasn't landed them yet. Order matches the
        // sorted-uid convention used everywhere else: lower uid is user1.
        let key = try c.decode(String.self, forKey: .id)
        let halves = key.split(separator: "_").map(String.init)

        id = key
        coupleId = try c.decodeIfPresent(String.self, forKey: .coupleId) ?? key
        user1Id = try c.decodeIfPresent(String.self, forKey: .user1Id)
            ?? (halves.count == 2 ? halves[0] : "")
        user2Id = try c.decodeIfPresent(String.self, forKey: .user2Id)
            ?? (halves.count == 2 ? halves[1] : "")

        user1Tasks = try c.decodeIfPresent([OnboardingTask].self, forKey: .user1Tasks) ?? []
        user1Submitted = try c.decodeIfPresent(Bool.self, forKey: .user1Submitted) ?? false
        user1Strikes = try c.decodeIfPresent([TaskStrike].self, forKey: .user1Strikes) ?? []
        user1ReviewComplete = try c.decodeIfPresent(Bool.self, forKey: .user1ReviewComplete) ?? false
        user1Confirmed = try c.decodeIfPresent(Bool.self, forKey: .user1Confirmed) ?? false

        user2Tasks = try c.decodeIfPresent([OnboardingTask].self, forKey: .user2Tasks) ?? []
        user2Submitted = try c.decodeIfPresent(Bool.self, forKey: .user2Submitted) ?? false
        user2Strikes = try c.decodeIfPresent([TaskStrike].self, forKey: .user2Strikes) ?? []
        user2ReviewComplete = try c.decodeIfPresent(Bool.self, forKey: .user2ReviewComplete) ?? false
        user2Confirmed = try c.decodeIfPresent(Bool.self, forKey: .user2Confirmed) ?? false

        finalTasks = try c.decodeIfPresent([CoupleTask].self, forKey: .finalTasks) ?? []
    }

    // MARK: - User Slot

    enum UserSlot {
        case user1, user2
    }

    func mySlot(userId: String) -> UserSlot {
        userId == user1Id ? .user1 : .user2
    }

    // MARK: - Convenience Accessors

    func myTasks(userId: String) -> [OnboardingTask] {
        mySlot(userId: userId) == .user1 ? user1Tasks : user2Tasks
    }

    func partnerTasks(userId: String) -> [OnboardingTask] {
        mySlot(userId: userId) == .user1 ? user2Tasks : user1Tasks
    }

    func iSubmitted(userId: String) -> Bool {
        mySlot(userId: userId) == .user1 ? user1Submitted : user2Submitted
    }

    func partnerSubmitted(userId: String) -> Bool {
        mySlot(userId: userId) == .user1 ? user2Submitted : user1Submitted
    }

    func myStrikes(userId: String) -> [TaskStrike] {
        mySlot(userId: userId) == .user1 ? user1Strikes : user2Strikes
    }

    func myReviewComplete(userId: String) -> Bool {
        mySlot(userId: userId) == .user1 ? user1ReviewComplete : user2ReviewComplete
    }

    func partnerReviewComplete(userId: String) -> Bool {
        mySlot(userId: userId) == .user1 ? user2ReviewComplete : user1ReviewComplete
    }

    func iConfirmed(userId: String) -> Bool {
        mySlot(userId: userId) == .user1 ? user1Confirmed : user2Confirmed
    }

    func partnerConfirmed(userId: String) -> Bool {
        mySlot(userId: userId) == .user1 ? user2Confirmed : user1Confirmed
    }

    var bothSubmitted: Bool { user1Submitted && user2Submitted }
    var bothReviewComplete: Bool { user1ReviewComplete && user2ReviewComplete }
    var bothConfirmed: Bool { user1Confirmed && user2Confirmed }
}

// MARK: - Negotiation Phase (computed from document state)

enum NegotiationPhase: Equatable {
    case submission      // 5A: one or both haven't submitted tasks yet
    case review          // 5B: both submitted, one or both haven't finished reviewing
    case confirmation    // 5C: both reviewed, one or both haven't confirmed
    case complete        // both confirmed
}

extension OnboardingTasksDocument {
    var currentPhase: NegotiationPhase {
        if !bothSubmitted { return .submission }
        if !bothReviewComplete { return .review }
        if !bothConfirmed { return .confirmation }
        return .complete
    }
}

// MARK: - App-Suggested Replacement Tasks

struct AppSuggestedTasks {
    static let pool: [String] = [
        "Do the laundry 🧺",
        "Clean the bathroom 🚿",
        "Make the bed for a week 🛏️",
        "Buy them their favorite snack 🍫",
        "Give a 10-minute foot rub 🦶",
        "Write 5 things you appreciate about them 💌",
        "Let them pick what to watch tonight 📺",
        "Make them coffee/tea for a week ☕",
        "No phone during dinner for a week 📵",
        "Plan a surprise date 🎉",
        "Do their least favorite chore 😤",
        "Breakfast in bed 🥐",
        "Give them a genuine 50-word apology ✍️",
        "Walk the dog solo for a week 🐕‍🦺",
        "30-minute uninterrupted listening session 👂",
    ]

    /// Return random unique suggestions, excluding any titles already in use
    static func randomSuggestion(excluding existingTitles: Set<String>) -> String {
        let available = pool.filter { !existingTitles.contains($0) }
        return available.randomElement() ?? pool.randomElement()!
    }
}
