//
//  ShopService.swift
//  DogHouse
//
//  Handles cosmetic purchases and equipping. State is read from AuthService.userProfile;
//  this service only performs writes.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

class ShopService {
    private let cf = CloudFunctions.shared

    // MARK: - Purchase (self or gift to partner)

    /// Buy a cosmetic. `forPartner` gifts it into the partner's wardrobe.
    /// Treats are validated and deducted server-side.
    func purchase(_ item: CosmeticItem, forPartner: Bool = false) async throws {
        try await cf.call("purchaseCosmetic", [
            "itemId": item.id,
            "forPartner": forPartner
        ])
    }

    // MARK: - Equip / Unequip (self or partner)

    func equipOnSelf(_ item: CosmeticItem) async throws {
        try await cf.call("equipCosmetic", [
            "itemId": item.id, "category": item.category.rawValue, "forPartner": false
        ])
    }

    func unequipOnSelf(category: CosmeticCategory) async throws {
        try await cf.call("equipCosmetic", [
            "itemId": NSNull(), "category": category.rawValue, "forPartner": false
        ])
    }

    func equipOnPartner(_ item: CosmeticItem, partnerId: String) async throws {
        try await cf.call("equipCosmetic", [
            "itemId": item.id, "category": item.category.rawValue, "forPartner": true
        ])
    }

    func unequipOnPartner(category: CosmeticCategory, partnerId: String) async throws {
        try await cf.call("equipCosmetic", [
            "itemId": NSNull(), "category": category.rawValue, "forPartner": true
        ])
    }

    // MARK: - Treat Earning

    /// Claim treats for time spent at home. The server computes the amount
    /// from event history; the client only passes the level-based rate.
    func awardHomeTreats(lastAward: Date?, treatsPerHour: Int) async throws {
        try await cf.call("claimHomeTreats", ["treatsPerHour": treatsPerHour])
    }
}

// MARK: - Errors

enum ShopError: LocalizedError {
    case insufficientTreats

    var errorDescription: String? {
        "Not enough treats! Keep playing to earn more 🦴"
    }
}
