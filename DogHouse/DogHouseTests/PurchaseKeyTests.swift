//
//  PurchaseKeyTests.swift
//  DogHouseTests
//
//  The rule that decides whether a RevenueCat key may configure the SDK.
//  It is the only thing standing between a Test Store key and a shipped
//  build, so it gets its own test.
//

import Foundation
import Testing
@testable import DogHouse

struct PurchaseKeyTests {
    @Test("Placeholders and empty keys never enable the store")
    func placeholders() {
        for debug in [true, false] {
            #expect(!PurchaseService.isUsableKey("appl_REPLACE_ME", debug: debug))
            #expect(!PurchaseService.isUsableKey("test_REPLACE_ME", debug: debug))
            #expect(!PurchaseService.isUsableKey("", debug: debug))
        }
    }

    @Test("Test Store keys are Debug-only")
    func testStoreKey() {
        #expect(PurchaseService.isUsableKey("test_abc123", debug: true))
        #expect(!PurchaseService.isUsableKey("test_abc123", debug: false))
    }

    @Test("App Store keys work in every build")
    func appStoreKey() {
        #expect(PurchaseService.isUsableKey("appl_abc123", debug: true))
        #expect(PurchaseService.isUsableKey("appl_abc123", debug: false))
    }

    @Test("Unknown prefixes are rejected")
    func unknownPrefix() {
        #expect(!PurchaseService.isUsableKey("sk_abc123", debug: true))
        #expect(!PurchaseService.isUsableKey("goog_abc123", debug: false))
    }
}
