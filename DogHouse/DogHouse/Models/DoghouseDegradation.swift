//
//  DoghouseDegradation.swift
//  DogHouse
//

import Foundation

enum DoghouseStage: Int, CaseIterable {
    case justArrived = 1
    case gettingHungry = 2
    case cloudsGathering = 3
    case rainy = 4
    case gettingDirty = 5
    case mouseFriend = 6
    case stormyNight = 7
    case fullSurvival = 8

    var name: String {
        switch self {
        case .justArrived: "Just Arrived"
        case .gettingHungry: "Getting Hungry"
        case .cloudsGathering: "Clouds Gathering"
        case .rainy: "Rainy Days"
        case .gettingDirty: "Getting Dirty"
        case .mouseFriend: "At Least There's Company"
        case .stormyNight: "The Storm"
        case .fullSurvival: "Full Survival Mode"
        }
    }

    var statusText: String {
        switch self {
        case .justArrived: "Thinking about what they did..."
        case .gettingHungry: "Stomach is rumbling..."
        case .cloudsGathering: "Dark clouds rolling in..."
        case .rainy: "It's raining. Great."
        case .gettingDirty: "Could really use a shower..."
        case .mouseFriend: "Made a new friend at least 🐭"
        case .stormyNight: "The storm has arrived ⛈️"
        case .fullSurvival: "Send help... 🥶"
        }
    }

    /// Time threshold in seconds
    var timeThreshold: TimeInterval {
        switch self {
        case .justArrived: 0
        case .gettingHungry: 3600          // 1 hour
        case .cloudsGathering: 10800       // 3 hours
        case .rainy: 21600                 // 6 hours
        case .gettingDirty: 86400          // 1 day
        case .mouseFriend: 259200          // 3 days
        case .stormyNight: 432000          // 5 days
        case .fullSurvival: 604800         // 7 days
        }
    }

    // Visual flags
    var showHunger: Bool { rawValue >= 2 }       // empty bowl + thought bubble
    var showClouds: Bool { rawValue >= 3 }       // dark clouds drift across the sky
    var showRain: Bool { rawValue >= 4 }
    var showPuddles: Bool { rawValue >= 4 }
    var showDirty: Bool { rawValue >= 5 }        // cobwebs + mud
    var showFlies: Bool { rawValue >= 5 }
    var showMouse: Bool { rawValue >= 6 }
    var showRoofPatch: Bool { rawValue >= 6 }    // the doghouse itself decays
    var showThunder: Bool { rawValue >= 7 }
    var showLeaves: Bool { rawValue >= 7 }       // wind-blown leaves
    var showShiver: Bool { rawValue >= 8 }
    var showSnow: Bool { rawValue >= 8 }         // rain turns to snow
    var showIcicles: Bool { rawValue >= 8 }

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
