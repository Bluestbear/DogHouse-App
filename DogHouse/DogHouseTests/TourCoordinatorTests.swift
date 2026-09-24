//
//  TourCoordinatorTests.swift
//  DogHouseTests
//
//  The live tour's script and state machine, without any UI.
//

import Foundation
import CoreGraphics
import Testing
@testable import DogHouse

@MainActor
struct TourCoordinatorTests {

    @Test("Starting shows the first step")
    func startShowsFirstStep() {
        let tour = TourCoordinator()
        #expect(!tour.isActive)
        tour.start()
        #expect(tour.isActive)
        #expect(tour.currentStep == TourStep.allCases.first)
    }

    @Test("Next walks every step in order and finishes exactly once")
    func nextWalksAllSteps() {
        let tour = TourCoordinator()
        tour.start()
        for expected in TourStep.allCases {
            #expect(tour.currentStep == expected)
            tour.next()
        }
        #expect(tour.currentStep == nil)
        #expect(tour.completionCount == 1)

        // Nothing is running; a stray Next must not count as another completion.
        tour.next()
        #expect(tour.completionCount == 1)
    }

    @Test("Back never leaves the first step")
    func backStopsAtFirst() {
        let tour = TourCoordinator()
        tour.start()
        tour.back()
        #expect(tour.currentStep == .welcome)
        tour.next()
        tour.back()
        #expect(tour.currentStep == .welcome)
    }

    @Test("Skip ends the tour from the middle and counts as complete")
    func skipFinishes() {
        let tour = TourCoordinator()
        tour.start()
        tour.next()
        tour.next()
        tour.skip()
        #expect(tour.currentStep == nil)
        #expect(tour.completionCount == 1)
    }

    @Test("Replay is a normal run that remembers it was a replay")
    func replayFlag() {
        let tour = TourCoordinator()
        tour.start(replay: true)
        #expect(tour.isReplay)
        #expect(tour.currentStep == .welcome)
    }

    @Test("Ordinals are one-based and cover the whole script")
    func ordinals() {
        #expect(TourStep.allCases.first?.ordinal == 1)
        #expect(TourStep.allCases.last?.ordinal == TourStep.count)
        #expect(TourStep.allCases.last?.isLast == true)
        #expect(TourStep.allCases.first?.isFirst == true)
    }

    @Test("Each spotlighted step sits on the tab its control lives on")
    func stepsMatchTabs() {
        #expect(TourStep.shop.tab == .shop)
        #expect(TourStep.shop.anchor == .treatBalance)
        #expect(TourStep.friends.tab == .friends)
        #expect(TourStep.friends.anchor == .addCouple)
        #expect(TourStep.anniversary.tab == .profile)
        #expect(TourStep.anniversary.anchor == .anniversary)
        #expect(TourStep.input.tab == .profile)
        #expect(TourStep.sendButton.tab == .home)
        #expect(TourStep.sendButton.anchor == .sendButton)
    }

    @Test("Partner-page steps flip the scene window; others leave it alone")
    func scenePages() {
        #expect(TourStep.partnerRoom.scenePage == 1)
        #expect(TourStep.roses.scenePage == 1)
        // The send button lives under the partner's page, so its step has to
        // flip there too or the spotlight lands on nothing.
        #expect(TourStep.sendButton.scenePage == 1)
        #expect(TourStep.myRoom.scenePage == 0)
        #expect(TourStep.treats.scenePage == 0)
        #expect(TourStep.shop.scenePage == nil)
    }

    @Test("Every step that spotlights a page-specific control names its page")
    func pageSpecificAnchorsSetAPage() {
        // These anchors only exist on one page of the scene window; a step
        // pointing at one without a scenePage would spotlight empty space.
        let pageSpecific: Set<TourAnchorID> = [.rosesButton, .sendButton, .roomProgress]
        for step in TourStep.allCases {
            guard let anchor = step.anchor, pageSpecific.contains(anchor) else { continue }
            #expect(step.scenePage != nil, "\(step) spotlights \(anchor) but sets no scene page")
        }
    }

    @Test("Copy fills in the couple's real names")
    func copyUsesNames() {
        let welcome = TourStep.welcome.content(userName: "Ari", partnerName: "Sam")
        #expect(welcome.title.contains("Ari"))

        let partner = TourStep.partnerRoom.content(userName: "Ari", partnerName: "Sam")
        #expect(partner.title.contains("Sam"))

        for step in TourStep.allCases {
            let content = step.content(userName: "Ari", partnerName: "Sam")
            #expect(!content.title.isEmpty)
            #expect(!content.body.isEmpty)
        }
    }

    @Test("Anchor store keeps frames and ignores sub-pixel jitter")
    func anchorStore() {
        let store = TourAnchorStore()
        let frame = CGRect(x: 10, y: 20, width: 100, height: 40)
        store.register(.sendButton, frame: frame)
        #expect(store.frames[.sendButton] == frame)

        store.register(.sendButton, frame: frame.offsetBy(dx: 0.2, dy: 0.1))
        #expect(store.frames[.sendButton] == frame)

        let moved = frame.offsetBy(dx: 0, dy: 30)
        store.register(.sendButton, frame: moved)
        #expect(store.frames[.sendButton] == moved)

        store.unregister(.sendButton)
        #expect(store.frames[.sendButton] == nil)
    }
}
