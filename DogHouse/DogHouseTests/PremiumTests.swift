//
//  PremiumTests.swift
//  DogHouseTests
//
//  The client-side half of Premium: reading `premiumUntil`, and telling the
//  daily game limit apart from the other resource-exhausted error so the
//  composer only shows the paywall for the right one.
//

import Foundation
import Testing
@testable import DogHouse

struct PremiumTests {
    private func profile(premiumUntil: Double?) -> UserProfile {
        var p = UserProfile(id: "a", displayName: "A", avatarId: nil, partnerCode: nil, partnerId: "b",
                            immunityUntil: nil, friendIds: [], createdAt: Date(), fcmToken: nil)
        p.premiumUntil = premiumUntil
        return p
    }

    private var nowMs: Double { Date().timeIntervalSince1970 * 1000 }

    @Test func premiumUntilInTheFutureIsActive() {
        #expect(profile(premiumUntil: nowMs + 60_000).isPremiumActive)
    }

    @Test func expiredOrMissingPremiumIsNotActive() {
        #expect(!profile(premiumUntil: nowMs - 60_000).isPremiumActive)
        #expect(!profile(premiumUntil: nil).isPremiumActive)
    }

    @Test func dailyLimitIsMatchedOnReason() {
        let error = NSError(domain: "CloudFunctions", code: 8 /* resourceExhausted */,
                            userInfo: [NSLocalizedDescriptionKey: "daily-game-limit",
                                       "details" /* FunctionsErrorDetailsKey */: ["reason": "daily-game-limit"]])
        #expect(ChallengeService.DailyGameLimitError.matches(error))
    }

    @Test func tooManyActiveGamesIsNotTheDailyLimit() {
        let error = NSError(domain: "CloudFunctions", code: 8 /* resourceExhausted */,
                            userInfo: [NSLocalizedDescriptionKey:
                                        "You have lots of games waiting already. Let your partner catch up first!"])
        #expect(!ChallengeService.DailyGameLimitError.matches(error))
    }
}
