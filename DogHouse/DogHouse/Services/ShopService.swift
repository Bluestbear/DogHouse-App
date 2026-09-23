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
        AnalyticsService.shared.log(.purchaseCosmetic, [
            "item_id": item.id,
            "category": item.category.rawValue,
            "price": item.price,
            "gifted": forPartner
        ])
    }

    // MARK: - Equip / Unequip (own dog only; gifts are the partner's to wear)

    func equipOnSelf(_ item: CosmeticItem) async throws {
        try await cf.call("equipCosmetic", [
            "itemId": item.id, "category": item.category.rawValue, "forPartner": false
        ])
        AnalyticsService.shared.log(.equipCosmetic, ["item_id": item.id, "on_partner": false])
    }

    func unequipOnSelf(category: CosmeticCategory) async throws {
        try await cf.call("equipCosmetic", [
            "itemId": NSNull(), "category": category.rawValue, "forPartner": false
        ])
    }

    // MARK: - Treat Earning

    /// Claim treats for time spent at home. The server computes both the
    /// hours and the room-level rate from event history; nothing the client
    /// sends affects the amount.
    func awardHomeTreats() async throws {
        let result = try await cf.call("claimHomeTreats")
        AnalyticsService.shared.log(.claimTreats, ["awarded": result["awarded"] as? Int ?? 0])
    }
}
