//
//  KickClockTests.swift
//  DogHouseTests
//
//  The send-to-doghouse kick must not skip its wind-up when a frame hitches.
//

import Foundation
import Testing
@testable import DogHouse

@MainActor
struct KickClockTests {

    @Test("Frames advance the clock by real time")
    func tracksFrames() {
        let clock = KickClock()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(clock.advance(to: start) == 0)
        let t = clock.advance(to: start.addingTimeInterval(1.0 / 60))
        #expect(abs(t - 1.0 / 60) < 1e-9)
    }

    @Test("A long hitch pauses the kick instead of skipping ahead")
    func hitchIsClamped() {
        let clock = KickClock()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        _ = clock.advance(to: start)
        let t = clock.advance(to: start.addingTimeInterval(2))
        #expect(t < KickTimeline.windUp.lowerBound)
        #expect(t <= 1.0 / 20 + 1e-9)
    }

    @Test("Time never runs backwards")
    func monotonic() {
        let clock = KickClock()
        let start = Date(timeIntervalSinceReferenceDate: 10)
        _ = clock.advance(to: start)
        let a = clock.advance(to: start.addingTimeInterval(0.03))
        let b = clock.advance(to: start)
        #expect(b == a)
    }

    @Test("The boot's swing lands before the dog flies")
    func timelineOrder() {
        #expect(KickTimeline.windUp.upperBound <= KickTimeline.swing.lowerBound)
        #expect(KickTimeline.contact == KickTimeline.flight.lowerBound)
        #expect(KickTimeline.flight.upperBound < KickTimeline.textIn.lowerBound)
        #expect(KickTimeline.textIn.upperBound < KickTimeline.fadeOut.lowerBound)
    }
}
