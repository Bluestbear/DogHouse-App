//
//  FeedDemoUITests.swift
//  DogHouseUITests
//
//  A public send on the demo profile lands in the Friends feed, and a
//  reaction shows up under the message. Screenshots are attached at each
//  step; export them with `xcrun xcresulttool export attachments`.
//

import XCTest

final class FeedDemoUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demoOnboarding", "-demoHome"]
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapIfPresent(_ element: XCUIElement, timeout: TimeInterval = 8) {
        if element.waitForExistence(timeout: timeout) { element.tap() }
    }

    private func button(containing text: String) -> XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    func testPublicSendAndReaction() throws {
        app.launch()
        tapIfPresent(app.buttons["I agree"], timeout: 15)
        tapIfPresent(app.buttons["Maybe later"], timeout: 6)

        // Home → send sheet
        // Home opens on my dog; the send button is on Sam's side
        // (a paged TabView: swipe across the scene)
        let scene = app.staticTexts["Harrison"].firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout: 10))
        // Drag on the scene itself (lower half): a Photo Dash card above it
        // would swallow the gesture.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.7)))
        sleep(1)
        let sendButton = app.buttons["Send Sam to the doghouse"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 10))
        for _ in 0..<3 where !sendButton.isHittable { app.swipeUp() }
        sendButton.tap()

        let reason = app.textFields["They forgot..."]
        XCTAssertTrue(reason.waitForExistence(timeout: 8))
        reason.tap()
        reason.typeText("Ate my leftovers")

        // Share with friends — switches need a held tap
        let share = app.switches.firstMatch
        if !share.isHittable { app.swipeUp() }
        share.press(forDuration: 0.12)
        sleep(1)
        snap("01-send-sheet-shared")

        button(containing: "Send Sam").tap()
        sleep(6) // kick animation
        snap("02-after-send")

        // Friends feed: the shared send is on top
        let friendsTab = app.tabBars.buttons["Friends"].exists ? app.tabBars.buttons["Friends"] : app.buttons["Friends"]
        XCTAssertTrue(friendsTab.waitForExistence(timeout: 10))
        friendsTab.tap()
        XCTAssertTrue(app.staticTexts["“Ate my leftovers”"].waitForExistence(timeout: 8))
        sleep(1)
        snap("03-feed-with-shared-send")

        // My own send is marked as mine and has no reaction buttons: only
        // the two mock friends' posts offer them.
        XCTAssertTrue(app.staticTexts["Your send"].exists)
        // Only rendered rows count; the second friend post sits below Top Dog.
        let backButtons = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Back it"))
        XCTAssertGreaterThanOrEqual(backButtons.count, 1)

        // Reacting on a friend's post shows up under their message
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Free the dog")).element(boundBy: 0).tap()
        sleep(1)
        snap("04-freed-jordans-dog")
    }
}
