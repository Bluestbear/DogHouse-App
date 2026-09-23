//
//  Cosmetic.swift
//  DogHouse
//

import SwiftUI

// MARK: - Category

enum CosmeticCategory: String, CaseIterable, Codable {
    case necklace
    case hat
    case glasses

    var displayName: String {
        switch self {
        case .necklace: "Necklaces"
        case .hat:      "Hats"
        case .glasses:  "Glasses"
        }
    }

    var systemImage: String {
        switch self {
        case .necklace: "sparkles"
        case .hat:      "theatermasks"
        case .glasses:  "eyeglasses"
        }
    }
}

// MARK: - Item

struct CosmeticItem: Identifiable {
    let id: String
    let name: String
    let category: CosmeticCategory
    let price: Int
    let primaryColor: Color
    let accentColor: Color
    let emoji: String

    // MARK: Catalog

    static let catalog: [CosmeticItem] = [
        // Necklaces
        .init(id: "necklace_red",     name: "Ruby",        category: .necklace, price: 50,  primaryColor: Color(red: 0.85, green: 0.15, blue: 0.15), accentColor: Color(red: 0.60, green: 0.05, blue: 0.05), emoji: "🔴"),
        .init(id: "necklace_blue",    name: "Sapphire",    category: .necklace, price: 50,  primaryColor: Color(red: 0.15, green: 0.35, blue: 0.90), accentColor: Color(red: 0.08, green: 0.18, blue: 0.60), emoji: "🔵"),
        .init(id: "necklace_green",   name: "Emerald",     category: .necklace, price: 50,  primaryColor: Color(red: 0.10, green: 0.72, blue: 0.35), accentColor: Color(red: 0.05, green: 0.48, blue: 0.20), emoji: "🟢"),
        .init(id: "necklace_purple",  name: "Amethyst",    category: .necklace, price: 75,  primaryColor: Color(red: 0.62, green: 0.18, blue: 0.88), accentColor: Color(red: 0.40, green: 0.08, blue: 0.60), emoji: "🟣"),
        .init(id: "necklace_pink",    name: "Rose Quartz", category: .necklace, price: 75,  primaryColor: Color(red: 0.95, green: 0.42, blue: 0.65), accentColor: Color(red: 0.72, green: 0.20, blue: 0.42), emoji: "🩷"),
        .init(id: "necklace_gold",    name: "Gold Chain",  category: .necklace, price: 120, primaryColor: Color(red: 0.95, green: 0.78, blue: 0.12), accentColor: Color(red: 0.75, green: 0.55, blue: 0.05), emoji: "✨"),
        .init(id: "necklace_bone",    name: "Bone Charm",  category: .necklace, price: 60,  primaryColor: Color(red: 0.95, green: 0.92, blue: 0.83), accentColor: Color(red: 0.80, green: 0.76, blue: 0.64), emoji: "🦴"),
        .init(id: "necklace_heart",   name: "Heart Locket",category: .necklace, price: 90,  primaryColor: Color(red: 0.93, green: 0.28, blue: 0.45), accentColor: Color(red: 0.72, green: 0.12, blue: 0.28), emoji: "❤️"),
        .init(id: "necklace_rainbow", name: "Rainbow",     category: .necklace, price: 200, primaryColor: Color(red: 0.95, green: 0.20, blue: 0.20), accentColor: Color(red: 0.20, green: 0.55, blue: 0.95), emoji: "🌈"),
        .init(id: "necklace_diamond", name: "Diamond",     category: .necklace, price: 300, primaryColor: Color(red: 0.70, green: 0.90, blue: 0.98), accentColor: Color(red: 0.45, green: 0.72, blue: 0.90), emoji: "💎"),
        // Hats
        .init(id: "hat_beanie", name: "Cozy Beanie", category: .hat, price: 70,  primaryColor: Color(red: 0.80, green: 0.32, blue: 0.30), accentColor: Color(red: 0.62, green: 0.20, blue: 0.20), emoji: "🧢"),
        .init(id: "hat_party",  name: "Party Hat",  category: .hat, price: 80,  primaryColor: Color(red: 0.95, green: 0.28, blue: 0.28), accentColor: Color(red: 0.20, green: 0.52, blue: 0.95), emoji: "🥳"),
        .init(id: "hat_cowboy", name: "Cowboy Hat", category: .hat, price: 100, primaryColor: Color(red: 0.52, green: 0.32, blue: 0.12), accentColor: Color(red: 0.30, green: 0.18, blue: 0.06), emoji: "🤠"),
        .init(id: "hat_chef",   name: "Chef's Hat", category: .hat, price: 100, primaryColor: .white,                                    accentColor: Color(red: 0.62, green: 0.62, blue: 0.62), emoji: "👨‍🍳"),
        .init(id: "hat_wizard", name: "Wizard Hat", category: .hat, price: 180, primaryColor: Color(red: 0.36, green: 0.22, blue: 0.60), accentColor: Color(red: 0.95, green: 0.82, blue: 0.25), emoji: "🧙"),
        .init(id: "hat_halo",   name: "Halo",       category: .hat, price: 220, primaryColor: Color(red: 0.98, green: 0.88, blue: 0.35), accentColor: Color(red: 0.90, green: 0.72, blue: 0.20), emoji: "😇"),
        .init(id: "hat_crown",  name: "Crown",      category: .hat, price: 250, primaryColor: Color(red: 0.98, green: 0.80, blue: 0.10), accentColor: Color(red: 0.85, green: 0.18, blue: 0.18), emoji: "👑"),
        // Glasses
        .init(id: "glasses_cool",  name: "Cool Shades",  category: .glasses, price: 80,  primaryColor: Color(red: 0.10, green: 0.10, blue: 0.10), accentColor: Color(red: 0.30, green: 0.30, blue: 0.30), emoji: "😎"),
        .init(id: "glasses_round", name: "Round Specs",  category: .glasses, price: 90,  primaryColor: Color(red: 0.20, green: 0.18, blue: 0.16), accentColor: Color(red: 0.45, green: 0.40, blue: 0.34), emoji: "🤓"),
        .init(id: "glasses_heart", name: "Heart Frames", category: .glasses, price: 100, primaryColor: Color(red: 0.92, green: 0.20, blue: 0.40), accentColor: Color(red: 0.70, green: 0.08, blue: 0.25), emoji: "🩷"),
        .init(id: "glasses_ski",   name: "Ski Goggles",  category: .glasses, price: 110, primaryColor: Color(red: 0.20, green: 0.55, blue: 0.85), accentColor: Color(red: 0.95, green: 0.55, blue: 0.20), emoji: "🥽"),
        .init(id: "glasses_star",  name: "Star Frames",  category: .glasses, price: 120, primaryColor: Color(red: 0.95, green: 0.78, blue: 0.10), accentColor: Color(red: 0.75, green: 0.55, blue: 0.05), emoji: "⭐"),
    ]

    static func item(for id: String) -> CosmeticItem? {
        catalog.first { $0.id == id }
    }

    static func items(for category: CosmeticCategory) -> [CosmeticItem] {
        catalog.filter { $0.category == category }
    }
}

// MARK: - Equipped state

struct AvatarCosmetics: Equatable {
    var necklaceId: String?
    var hatId: String?
    var glassesId: String?

    static let none = AvatarCosmetics()

    init(necklaceId: String? = nil, hatId: String? = nil, glassesId: String? = nil) {
        self.necklaceId = necklaceId
        self.hatId = hatId
        self.glassesId = glassesId
    }

    init(equippedItemIds: [String: String]) {
        self.necklaceId = equippedItemIds[CosmeticCategory.necklace.rawValue]
        self.hatId      = equippedItemIds[CosmeticCategory.hat.rawValue]
        self.glassesId  = equippedItemIds[CosmeticCategory.glasses.rawValue]
    }

    var necklace: CosmeticItem? { necklaceId.flatMap { CosmeticItem.item(for: $0) } }
    var hat: CosmeticItem?      { hatId.flatMap      { CosmeticItem.item(for: $0) } }
    var glasses: CosmeticItem?  { glassesId.flatMap  { CosmeticItem.item(for: $0) } }
}
