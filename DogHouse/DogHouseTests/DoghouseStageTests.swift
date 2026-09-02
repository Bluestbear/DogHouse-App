//
//  DoghouseStageTests.swift
//  DogHouseTests
//
//  The doghouse gets worse the longer you are in it — and never better.
//

import Foundation
import Testing
@testable import DogHouse

struct DoghouseStageTests {

    @Test("Stages resolve at their thresholds")
    func thresholds() {
        #expect(DoghouseStage.stage(for: 0) == .justArrived)
        #expect(DoghouseStage.stage(for: 3599) == .justArrived)
        #expect(DoghouseStage.stage(for: 3600) == .gettingHungry)
        #expect(DoghouseStage.stage(for: 6 * 3600) == .rainy)
        #expect(DoghouseStage.stage(for: 5 * 86_400) == .stormyNight)
        #expect(DoghouseStage.stage(for: 30 * 86_400) == .fullSurvival)
    }

    @Test("Shivering only ever gets worse with time")
    func shiverStacks() {
        let levels = DoghouseStage.allCases.map(\.shiverLevel)
        #expect(levels == levels.sorted())
        #expect(DoghouseStage.justArrived.shiverLevel == 0)
        #expect(DoghouseStage.fullSurvival.shiverLevel == 3)
    }

    @Test("Rain builds from drizzle to storm, then eases into snow")
    func rainStacks() {
        let upToStorm = DoghouseStage.allCases.filter { $0.rawValue <= DoghouseStage.stormyNight.rawValue }
        let intensities = upToStorm.map(\.rainIntensity)
        #expect(intensities == intensities.sorted())
        #expect(DoghouseStage.justArrived.rainIntensity == 0)
        #expect(DoghouseStage.stormyNight.rainIntensity == 1)
        #expect(DoghouseStage.fullSurvival.showSnow)
        #expect(DoghouseStage.fullSurvival.rainIntensity > 0)
    }

    @Test("Lightning arrives on the horizon before it arrives overhead")
    func lightningStacks() {
        #expect(DoghouseStage.rainy.lightning == .none)
        #expect(DoghouseStage.mouseFriend.lightning == .distant)
        #expect(DoghouseStage.stormyNight.lightning == .storm)
        #expect(DoghouseStage.fullSurvival.lightning == .storm)
    }

    @Test("Gloom runs from 0 on arrival to 1 in full survival")
    func gloomRange() {
        #expect(DoghouseStage.justArrived.gloom == 0)
        #expect(DoghouseStage.fullSurvival.gloom == 1)
        let gloom = DoghouseStage.allCases.map(\.gloom)
        #expect(gloom == gloom.sorted())
    }
}
