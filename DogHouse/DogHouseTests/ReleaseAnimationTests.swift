//
//  ReleaseAnimationTests.swift
//  DogHouseTests
//
//  The release overlay picks one of two scenes at random, and each scene's
//  beats must land in order.
//

import Foundation
import Testing
@testable import DogHouse

struct ReleaseAnimationTests {

    @Test("Both release scenes turn up")
    func bothVariantsPicked() {
        let picks = Set((0..<200).map { _ in ReleaseVariant.pick() })
        #expect(picks == Set(ReleaseVariant.allCases))
    }

    @Test("Homecoming: peek, look, hop home, then shake and celebrate")
    func homecomingOrder() {
        typealias T = HomecomingTimeline
        #expect(T.peek.upperBound <= T.look.lowerBound)
        #expect(T.look.upperBound <= T.brighten)
        #expect(T.brighten < T.hops.lowerBound)
        #expect(T.landings.count == T.hopHeights.count)
        #expect(abs(T.landings.last! - T.hops.upperBound) < 1e-9)
        #expect(T.hops.upperBound <= T.shake.lowerBound)
        #expect(T.beats.textIn.upperBound < T.beats.fadeOut.lowerBound)
    }

    @Test("Peace offering: boot arrives, nudges the treat, leaves before the party")
    func offeringOrder() {
        typealias T = OfferingTimeline
        #expect(T.bootIn.upperBound <= T.nudge.lowerBound)
        #expect(T.treatSlide.upperBound <= T.eat.lowerBound)
        #expect(T.brighten <= T.eat.lowerBound)
        #expect(T.eat.upperBound <= T.hop.lowerBound)
        #expect(T.bootOut.upperBound <= T.beats.heart.lowerBound)
        #expect(T.beats.textIn.upperBound < T.beats.fadeOut.lowerBound)
    }
}
