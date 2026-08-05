//
//  UserProfile.swift
//  DogHouse
//

import Foundation

struct UserProfile: Codable, Identifiable {
    var id: String
    var displayName: String
    var avatarId: String?
    /// LEGACY — the pairing code now lives in `UserPrivateData` on the
    /// owner-only /users/{uid}/private/data document. This stays only so
    /// documents written before the migration still decode; read the code
    /// from `AuthService.partnerCode` instead.
    var partnerCode: String?
    var partnerId: String?
    var immunityUntil: Date?
    var friendIds: [String]
    var createdAt: Date
    /// LEGACY — see `partnerCode`. Push tokens are device identifiers and
    /// must not sit on a document other accounts can read.
    var fcmToken: String?
    var graceCharges: Int?
    var lastGraceRecharge: Date?
    var tourComplete: Bool?
    var onboardingComplete: Bool?
    var treats: Int?
    var ownedItemIds: [String]?
    var equippedItemIds: [String: String]? // CosmeticCategory.rawValue -> itemId
    var lastTreatAward: Date?
    var wishCards: Int?

    /// Whether this user currently has active immunity from voting
    var hasImmunity: Bool {
        guard let immunityUntil else { return false }
        return immunityUntil > Date()
    }

    /// Maximum number of grace charges a user can hold
    static let maxGraceCharges = 3

    /// Current grace charges with auto-recharge calculation.
    /// Recharges 1 charge per 24 hours, up to maxGraceCharges.
    var effectiveGraceCharges: Int {
        let stored = graceCharges ?? Self.maxGraceCharges
        guard let lastRecharge = lastGraceRecharge else { return stored }
        let hoursSinceRecharge = Date().timeIntervalSince(lastRecharge) / 3600
        let rechargedCharges = Int(hoursSinceRecharge / 24) // 1 per day
        return min(stored + rechargedCharges, Self.maxGraceCharges)
    }

    var effectiveTreats: Int { treats ?? 100 }
    var ownedItemSet: Set<String> { Set(ownedItemIds ?? []) }
    var cosmetics: AvatarCosmetics { AvatarCosmetics(equippedItemIds: equippedItemIds ?? [:]) }

    // MARK: - Onboarding Helpers

    var hasSelectedAvatar: Bool { avatarId != nil }
    var isTourComplete: Bool { tourComplete ?? false }
    var isOnboardingComplete: Bool { onboardingComplete ?? false }
}

// MARK: - Private Data

/// Owner-only companion document at /users/{uid}/private/data. Readable and
/// writable by its owner alone; Cloud Functions reach it with admin
/// privileges. Nothing here may be duplicated back onto `UserProfile`.
struct UserPrivateData: Codable {
    /// This account's pairing code. Issued once at sign-up, immutable after.
    var partnerCode: String?
    /// FCM registration token for this account's current device.
    var fcmToken: String?
}
