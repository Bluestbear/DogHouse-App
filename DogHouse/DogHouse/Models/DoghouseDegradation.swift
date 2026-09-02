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

    // MARK: Stacked weather
    // Each of these only ever gets worse with time served, so the scene can
    // layer them: drizzle joins the clouds, becomes rain, then a storm with
    // lightning, and finally snow — while the dog shivers harder throughout.

    /// 0 = dry, 1 = downpour. Snow at the final stage falls more gently.
    var rainIntensity: Double {
        switch self {
        case .justArrived, .gettingHungry: 0
        case .cloudsGathering: 0.3
        case .rainy: 0.6
        case .gettingDirty, .mouseFriend: 0.8
        case .stormyNight: 1.0
        case .fullSurvival: 0.7
        }
    }

    /// 0 = still, 3 = teeth chattering.
    var shiverLevel: Int {
        switch self {
        case .justArrived, .gettingHungry, .cloudsGathering: 0
        case .rainy, .gettingDirty: 1
        case .mouseFriend, .stormyNight: 2
        case .fullSurvival: 3
        }
    }

    enum Lightning { case none, distant, storm }

    /// Distant flashes on the horizon first, then bolts overhead.
    var lightning: Lightning {
        rawValue >= 7 ? .storm : rawValue >= 6 ? .distant : .none
    }

    var isNight: Bool { rawValue >= 6 }

    /// 0 = calm, 1 = gale. Tilts the rain and shakes the tree.
    var windStrength: Double {
        rawValue >= 7 ? 1 : rawValue >= 5 ? 0.4 : 0
    }

    /// How far into the misery we are, 0...1 — drives every colour in the scene.
    var gloom: Double { Double(rawValue - 1) / Double(DoghouseStage.allCases.count - 1) }

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
