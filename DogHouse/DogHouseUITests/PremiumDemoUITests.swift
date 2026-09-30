//
//  PremiumDemoUITests.swift
//  DogHouseUITests
//
//  DogHouse Premium on the demo couple (`-demoOnboarding -demoHome -demoPlay`,
//  nothing reaches Firebase or StoreKit): a free couple's Save opens the
//  paywall, the first game of the day sends, the second opens the paywall,
//  subscribing lifts the limit, and Save then lands the Photo Dash in Photos.
//  Screenshots are attached at each step; export them with
//  `xcrun xcresulttool export attachments`.
//

import XCTest

final class PremiumDemoUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demoOnboarding", "-demoHome", "-demoPlay"]
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

    private func tab(_ name: String) -> XCUIElement {
        app.tabBars.buttons[name].exists ? app.tabBars.buttons[name] : app.buttons[name]
    }

    /// Opens the likelyTo composer (its prompt is pre-filled), picks "Me" and sends.
    private func composeAndSend() {
        let tile = button(containing: "Who's More Likely To")
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        // The fourth tile in a horizontal row: drag the row until it's on screen.
        let screen = app.windows.firstMatch.frame
        for _ in 0..<4 where tile.frame.maxX > screen.maxX {
            let y = tile.frame.midY / screen.height
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: y))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: y)))
            sleep(1)
        }
        tile.tap()
        let me = app.buttons["Me"].firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 8))
        me.tap()
        app.buttons["Send"].tap()
    }

    private var paywallHeadline: XCUIElement {
        app.staticTexts["DogHouse Premium, for both of you"]
    }

    @MainActor
    func testFreeLimitPaywallSubscribeAndSave() throws {
        // The Photos add-only permission prompt comes from SpringBoard.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        app.launch()
        tapIfPresent(app.buttons["I agree"], timeout: 12)
        tapIfPresent(app.buttons["Maybe later"], timeout: 5)

        // 1. Free couple: the hint shows on Play.
        XCTAssertTrue(button(containing: "Who's More Likely To").waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "One free game a day")).firstMatch.exists)
        snap("01-play-free-hint")

        // 2. Free couple: Save on the Photo Dash opens the paywall.
        tab("Home").tap()
        let save = app.buttons["Save photo to your library"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        snap("02-home-photo-dash")
        save.tap()
        XCTAssertTrue(paywallHeadline.waitForExistence(timeout: 8))
        sleep(1)
        snap("03-paywall-from-save")
        app.buttons["Close"].tap()

        // 3. Today's free game sends.
        tab("Play").tap()
        composeAndSend()
        XCTAssertTrue(button(containing: "Who's More Likely To").waitForExistence(timeout: 8))
        sleep(1)
        snap("04-first-game-sent")

        // 4. The second one hits the limit: paywall.
        composeAndSend()
        XCTAssertTrue(paywallHeadline.waitForExistence(timeout: 8))
        sleep(1)
        snap("05-paywall-game-limit")
        app.swipeUp()
        sleep(1)
        snap("06-paywall-terms")
        app.swipeDown()

        // 5. Subscribe (yearly, 7-day trial, preselected).
        let start = app.buttons["Start free trial"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let letsPlay = app.buttons["Let's play"]
        XCTAssertTrue(letsPlay.waitForExistence(timeout: 8))
        sleep(1)
        snap("07-premium-on")
        letsPlay.tap()

        // 6. Back in the composer, the same draft now sends: unlimited.
        let send = app.buttons["Send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        XCTAssertTrue(button(containing: "Who's More Likely To").waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "One free game a day")).firstMatch.exists)
        composeAndSend()
        XCTAssertTrue(button(containing: "Who's More Likely To").waitForExistence(timeout: 8))
        XCTAssertFalse(paywallHeadline.exists)
        sleep(1)
        snap("08-play-unlimited")

        // 7. Premium: Save lands the photo in Photos.
        tab("Home").tap()
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        for label in ["Allow", "Erlauben", "OK", "Allow Access"] { // this sim runs in German
            let allow = springboard.buttons[label]
            if allow.waitForExistence(timeout: 3) { allow.tap(); break }
        }
        XCTAssertTrue(app.buttons["Photo saved"].waitForExistence(timeout: 10))
        sleep(1)
        snap("09-photo-saved")

        // 8. Settings shows the subscription.
        tab("Profile").tap()
        let status = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "for you both")).firstMatch
        for _ in 0..<6 where !status.exists { app.swipeUp() }
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        sleep(1)
        snap("10-settings-premium")
    }

    /// `-demoPremium`: the demo couple starts subscribed (for recording the premium side).
    @MainActor
    func testDemoPremiumStartsUnlocked() throws {
        app.launchArguments.append("-demoPremium")
        app.launch()
        tapIfPresent(app.buttons["I agree"], timeout: 12)
        tapIfPresent(app.buttons["Maybe later"], timeout: 5)
        XCTAssertTrue(button(containing: "Who's More Likely To").waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "One free game a day")).firstMatch.exists)
        snap("P-demoPremium-play")
        composeAndSend()
        XCTAssertTrue(button(containing: "Who's More Likely To").waitForExistence(timeout: 8))
        composeAndSend()
        XCTAssertTrue(button(containing: "Who's More Likely To").waitForExistence(timeout: 8))
        XCTAssertFalse(paywallHeadline.exists)
        tab("Profile").tap()
        let status = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "for you both")).firstMatch
        for _ in 0..<6 where !status.exists { app.swipeUp() }
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        snap("P-demoPremium-settings")
    }
}
