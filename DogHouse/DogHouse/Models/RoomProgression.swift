//
//  RoomProgression.swift
//  DogHouse
//

import Foundation

enum RoomLevel: Int, CaseIterable {
    case bareBones = 1
    case basicChair = 2
    case blanket = 3
    case pillowAndRug = 4
    case fireplace = 5
    case tvAndArt = 6
    case plantsAndBooks = 7
    case luxury = 8
    case penthouse = 9
    case palace = 10

    var name: String {
        switch self {
        case .bareBones: "Bare Bones"
        case .basicChair: "Settling In"
        case .blanket: "Getting Cozy"
        case .pillowAndRug: "Comfort Zone"
        case .fireplace: "Warm & Toasty"
        case .tvAndArt: "Home Sweet Home"
        case .plantsAndBooks: "Living the Dream"
        case .luxury: "VIP Lounge"
        case .penthouse: "Penthouse Vibes"
        case .palace: "Dog Palace"
        }
    }

    var unlockMessage: String {
        switch self {
        case .bareBones: "Starting fresh..."
        case .basicChair: "A chair appears!"
        case .blanket: "A cozy blanket!"
        case .pillowAndRug: "Pillow & rug unlocked!"
        case .fireplace: "Fireplace is lit!"
        case .tvAndArt: "TV & wall art!"
        case .plantsAndBooks: "Plants & bookshelves!"
        case .luxury: "Full luxury! VIP status!"
        case .penthouse: "Penthouse! Aquarium & sunset views!"
        case .palace: "DOG PALACE! Pure royalty 👑"
        }
    }

    /// Time threshold in seconds to reach this level
    var timeThreshold: TimeInterval {
        switch self {
        case .bareBones: 0
        case .basicChair: 3600              // 1 hour
        case .blanket: 21600                // 6 hours
        case .pillowAndRug: 86400           // 1 day
        case .fireplace: 259200             // 3 days
        case .tvAndArt: 604800              // 7 days
        case .plantsAndBooks: 1209600       // 14 days
        case .luxury: 2592000               // 30 days
        case .penthouse: 5184000            // 60 days
        case .palace: 7776000               // 90 days
        }
    }

    /// Treats earned per hour at home — grows with room level, so a
    /// doghouse stint (which resets the room) also craters your income.
    var treatsPerHour: Int {
        switch self {
        case .bareBones, .basicChair: 1
        case .blanket, .pillowAndRug: 2
        case .fireplace, .tvAndArt: 3
        case .plantsAndBooks, .luxury: 4
        case .penthouse, .palace: 5
        }
    }

    /// The next level, if any
    var next: RoomLevel? {
        RoomLevel(rawValue: rawValue + 1)
    }

    /// Time remaining until the next level unlocks
    func timeToNextLevel(currentTime: TimeInterval) -> TimeInterval? {
        guard let next else { return nil }
        let remaining = next.timeThreshold - currentTime
        return remaining > 0 ? remaining : 0
    }

    /// Determine the current room level for a given duration out of the doghouse
    static func level(for duration: TimeInterval) -> RoomLevel {
        let sorted = allCases.reversed()
        for level in sorted {
            if duration >= level.timeThreshold {
                return level
            }
        }
        return .bareBones
    }

    // Visual element flags
    var hasChair: Bool { rawValue >= 2 }
    var hasBlanket: Bool { rawValue >= 3 }
    var hasPillow: Bool { rawValue >= 4 }
    var hasRug: Bool { rawValue >= 4 }
    var hasFireplace: Bool { rawValue >= 5 }
    var hasTV: Bool { rawValue >= 6 }
    var hasWallArt: Bool { rawValue >= 6 }
    var hasPlants: Bool { rawValue >= 7 }
    var hasBookshelf: Bool { rawValue >= 7 }
    var hasLuxury: Bool { rawValue >= 8 }
    var hasAquarium: Bool { rawValue >= 9 }
    var hasFloorLamp: Bool { rawValue >= 9 }
    var hasSunsetWindow: Bool { rawValue >= 9 }
    var hasRedCarpet: Bool { rawValue >= 10 }
    var hasGoldStatue: Bool { rawValue >= 10 }
    var hasBanner: Bool { rawValue >= 10 }
}
