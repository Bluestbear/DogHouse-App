//
//  WheelGeometryTests.swift
//  DogHouseTests
//
//  The avatar wheel's placement maths.
//

import Foundation
import CoreGraphics
import SwiftUI
import Testing
@testable import DogHouse

struct WheelGeometryTests {
    let wheel = WheelGeometry()

    @Test("The chosen dog sits at the top: no offset, full size, upright")
    func topDog() {
        let p = wheel.placement(forSlotDistance: 0)
        #expect(p.offset == .zero)
        #expect(p.scale == 1)
        #expect(p.opacity == 1)
        #expect(p.rotation == .zero)
    }

    @Test("The next dog waits lower right, the previous one lower left")
    func neighboursFallDownTheArc() {
        let next = wheel.placement(forSlotDistance: 1)
        let previous = wheel.placement(forSlotDistance: -1)
        #expect(next.offset.width > 0)
        #expect(previous.offset.width < 0)
        #expect(next.offset.height > 0)
        #expect(previous.offset.height > 0)
        #expect(abs(next.offset.width) == abs(previous.offset.width))
        #expect(next.offset.height == previous.offset.height)
    }

    @Test("Dogs shrink, fade and lean the further they are from the top")
    func falloff() {
        let one = wheel.placement(forSlotDistance: 1)
        let two = wheel.placement(forSlotDistance: 2)
        #expect(one.scale < 1 && two.scale < one.scale)
        #expect(one.opacity < 1 && two.opacity < one.opacity)
        #expect(abs(two.scale - wheel.minScale) < 0.0001)
        #expect(one.rotation.degrees > 0)
        #expect(wheel.placement(forSlotDistance: -1).rotation.degrees < 0)
    }

    @Test("Falloff bottoms out instead of going negative")
    func clampsBeyondFadeSlots() {
        let far = wheel.placement(forSlotDistance: 5)
        #expect(abs(far.scale - wheel.minScale) < 0.0001)
        #expect(abs(far.opacity - wheel.minOpacity) < 0.0001)
    }

    @Test("The top dog draws above its neighbours")
    func zOrder() {
        #expect(wheel.placement(forSlotDistance: 0).zIndex > wheel.placement(forSlotDistance: 1).zIndex)
        #expect(wheel.placement(forSlotDistance: -1).zIndex == wheel.placement(forSlotDistance: 1).zIndex)
    }

    @Test("One slot of drag equals the arc length between dogs")
    func dragDistance() {
        #expect(abs(wheel.pixelsPerSlot - wheel.radius * wheel.slotAngle.radians) < 0.0001)
    }
}
