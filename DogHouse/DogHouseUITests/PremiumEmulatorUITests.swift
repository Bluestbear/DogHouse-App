//
//  PremiumEmulatorUITests.swift
//  DogHouseUITests
//
//  DogHouse Premium against the LOCAL Firebase emulator (`-useEmulator`), on a
//  sim that is already signed in to an emulator account (the capture kit's
//  DH Luke). Nothing is demo-faked: the daily limit comes from createGame and
//  premium from `premiumUntil` written by the emulator's revenuecatWebhook.
//
//  Run one step at a time, with the webhook replay in between (see
//  Shipaton/PURCHASE_SEQUENCE.md, "Premium"):
//    1. testFreeCoupleIsLimited      one game sends, the next opens the paywall
//    2. node rc-premium.mjs start sarah   (the PARTNER subscribes)
//    3. testPartnerPremiumUnlocks     no hint, games send, Settings says "via Sarah"
//    4. node rc-premium.mjs expire sarah
//    5. testFreeCoupleIsLimited again
//

import XCTest

final class PremiumEmulatorUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-useEmulator"]
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func button(containing text: String) -> XCUIElement {
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func tab(_ name: String) -> XCUIElement {
        app.tabBars.buttons[name].exists ? app.tabBars.buttons[name] : app.buttons[name]
    }

    private var paywallHeadline: XCUIElement {
        app.staticTexts["DogHouse Premium, for both of you"]
    }

    private var freeHint: XCUIElement {
        button(containing: "One free game a day")
    }

    private func openPlay() {
        app.launch()
        let play = tab("Play")
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        play.tap()
        XCTAssertTrue(button(containing: "Who's More Likely To").waitForExistence(timeout: 10))
        sleep(2) // let the profile listeners deliver premiumUntil
    }

    /// Compose a likelyTo game and tap Send. Returns once the composer closed
    /// (sent) or the paywall appeared (limited).
    @discardableResult
    private func composeAndSend() -> Bool {
        let tile = button(containing: "Who's More Likely To")
        for _ in 0..<3 where !tile.isHittable {
            button(containing: "Ball Knowledge").firstMatch.swipeLeft()
        }
        tile.tap()
        let me = app.buttons["Me"].firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 8))
        me.tap()
        app.buttons["Send"].tap()
        for _ in 0..<40 {
            if paywallHeadline.exists { return false }
            if !app.buttons["Send"].exists && tile.exists { return true }
            usleep(250_000)
        }
        XCTFail("neither sent nor limited")
        return false
    }

    @MainActor
    func testFreeCoupleIsLimited() throws {
        openPlay()
        XCTAssertTrue(freeHint.exists, "a free couple sees the hint")
        snap("E1-free-play")

        // Whatever today's count is, a free couple is stopped by the second send at the latest.
        var limited = !composeAndSend()
        if !limited {
            snap("E2-free-game-sent")
            limited = !composeAndSend()
        }
        XCTAssertTrue(limited, "the server's daily limit opened the paywall")
        sleep(1)
        snap("E3-limited-paywall")
    }

    @MainActor
    func testPartnerPremiumUnlocks() throws {
        openPlay()
        XCTAssertFalse(freeHint.exists, "the partner's subscription covers this phone")
        snap("P1-premium-play")

        XCTAssertTrue(composeAndSend(), "premium couple: first send goes through")
        XCTAssertTrue(composeAndSend(), "premium couple: and the next")
        sleep(1)
        snap("P2-premium-unlimited")

        tab("Profile").tap()
        let status = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "via Sarah")).firstMatch
        for _ in 0..<6 where !status.exists { app.swipeUp() }
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        sleep(1)
        snap("P3-settings-via-partner")
    }
}
