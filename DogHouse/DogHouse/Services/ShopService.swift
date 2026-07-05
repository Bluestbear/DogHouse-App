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
    private let fs = FirebaseService.shared

    private var userId: String? { Auth.auth().currentUser?.uid }

    // MARK: - Purchase

    func purchase(_ item: CosmeticItem, currentTreats: Int) async throws {
        guard let uid = userId else { return }
        guard currentTreats >= item.price else {
            throw ShopError.insufficientTreats
        }
        let userRef = fs.usersCollection.document(uid)
        let batch = fs.db.batch()
        batch.updateData([
            "treats": FieldValue.increment(Int64(-item.price)),
            "ownedItemIds": FieldValue.arrayUnion([item.id])
        ], forDocument: userRef)
        try await batch.commit()
    }

    // MARK: - Equip / Unequip on self

    func equipOnSelf(_ item: CosmeticItem) async throws {
        guard let uid = userId else { return }
        try await fs.usersCollection.document(uid).updateData([
            "equippedItemIds.\(item.category.rawValue)": item.id
        ])
    }

    func unequipOnSelf(category: CosmeticCategory) async throws {
        guard let uid = userId else { return }
        try await fs.usersCollection.document(uid).updateData([
            "equippedItemIds.\(category.rawValue)": FieldValue.delete()
        ])
    }

    // MARK: - Equip / Unequip on partner

    // MARK: - Treat Earning

    /// Awards 10 treats for each complete hour spent at home since lastTreatAward.
    /// Idempotent: only runs if at least one hour has elapsed.
    func awardHomeTreats(lastAward: Date?) async throws {
        guard let uid = userId else { return }
        let now = Date()
        let since = lastAward ?? now.addingTimeInterval(-3600) // first time: award 1 hour
        let hoursElapsed = Int(now.timeIntervalSince(since) / 3600)
        guard hoursElapsed >= 1 else { return }
        let amount = hoursElapsed * 10
        try await fs.usersCollection.document(uid).updateData([
            "treats": FieldValue.increment(Int64(amount)),
            "lastTreatAward": Timestamp(date: now)
        ])
    }

    func equipOnPartner(_ item: CosmeticItem, partnerId: String) async throws {
        try await fs.usersCollection.document(partnerId).updateData([
            "equippedItemIds.\(item.category.rawValue)": item.id
        ])
    }

    func unequipOnPartner(category: CosmeticCategory, partnerId: String) async throws {
        try await fs.usersCollection.document(partnerId).updateData([
            "equippedItemIds.\(category.rawValue)": FieldValue.delete()
        ])
    }
}

// MARK: - Errors

enum ShopError: LocalizedError {
    case insufficientTreats

    var errorDescription: String? {
        "Not enough treats! Keep playing to earn more 🦴"
    }
}
