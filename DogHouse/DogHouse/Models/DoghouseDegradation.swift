//
//  DoghouseDegradation.swift
//  DogHouse
//

import Foundation

enum DoghouseStage: Int, CaseIterable {
    case justArrived = 1
    case gettingHungry = 2
    case rainy = 3
    case gettingDirty = 4
    case mouseFriend = 5
    case fullSurvival = 6

    var name: String {
        switch self {
        case .justArrived: "Just Arrived"
        case .gettingHungry: "Getting Hungry"
        case .rainy: "Rainy Days"
        case .gettingDirty: "Getting Dirty"
        case .mouseFriend: "At Least There's Company"
        case .fullSurvival: "Full Survival Mode"
        }
    }

    var statusText: String {
        switch self {
        case .justArrived: "Thinking about what they did..."
        case .gettingHungry: "Stomach is rumbling..."
        case .rainy: "It's raining. Great."
        case .gettingDirty: "Could really use a shower..."
        case .mouseFriend: "Made a new friend at least 🐭"
        case .fullSurvival: "Send help... 🥶"
        }
    }

    /// Time threshold in seconds
    var timeThreshold: TimeInterval {
        switch self {
        case .justArrived: 0
        case .gettingHungry: 3600          // 1 hour
        case .rainy: 21600                  // 6 hours
        case .gettingDirty: 86400           // 1 day
        case .mouseFriend: 259200           // 3 days
        case .fullSurvival: 604800          // 7 days
        }
    }

    // Visual flags
    var showHunger: Bool { rawValue >= 2 }
    var showRain: Bool { rawValue >= 3 }
    var showDirty: Bool { rawValue >= 4 }
    var showMouse: Bool { rawValue >= 5 }
    var showThunder: Bool { rawValue >= 6 }
    var showShiver: Bool { rawValue >= 6 }

    static func stage(for duration: TimeInterval) -> DoghouseStage {
        let sorted = allCases.reversed()
        for stage in sorted {
            if duration >= stage.timeThreshold {
                return stage
            }
        }
        return .justArrived
    }
}
