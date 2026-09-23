//
//  ShopDemoUITests.swift
//  DogHouseUITests
//
//  Drives the Shop and the treat store end-to-end on the demo profile
//  (`-demoOnboarding -demoHome`, no account, nothing reaches Firebase) and
//  attaches a screenshot at each step. Export them with
//  `xcrun xcresulttool export attachments`.
//

import XCTest

final class ShopDemoUITests: XCTestCase {

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
    func testShopAndTreatStore() throws {
        app.launch()

        // Demo mode does not persist the terms or the notification explainer.
        tapIfPresent(app.buttons["I agree"], timeout: 15)
        tapIfPresent(app.buttons["Maybe later"], timeout: 6)

        let shopTab = app.tabBars.buttons["Shop"].exists ? app.tabBars.buttons["Shop"] : app.buttons["Shop"]
        XCTAssertTrue(shopTab.waitForExistence(timeout: 10))
        shopTab.tap()
        XCTAssertTrue(app.buttons["Get more treats"].waitForExistence(timeout: 10))
        sleep(1)
        snap("01-shop-my-dog")

        // Dress the partner, then back.
        button(containing: "Sam's Dog").tap()
        sleep(1)
        snap("02-shop-partner-dog")
        button(containing: "My Dog").tap()

        // Hats: the beanie is owned but not worn — wear it.
        button(containing: "Hats").tap()
        sleep(1)
        snap("03-hats")
        tapIfPresent(app.buttons["Wear"].firstMatch)
        sleep(1)
        snap("04-hats-wearing-beanie")

        // Buy the first affordable hat (Party Hat, 80 treats).
        tapIfPresent(app.buttons["Buy"].firstMatch)
        sleep(2)
        snap("05-bought-party-hat")

        // Scroll to the priciest hats — out of reach at this balance.
        app.swipeUp()
        sleep(1)
        snap("06-hats-unaffordable")
        app.swipeDown()

        // Treat store.
        app.buttons["Get more treats"].tap()
        XCTAssertTrue(app.staticTexts["Treat Store"].waitForExistence(timeout: 8))
        sleep(1)
        snap("07-treat-store")

        button(containing: "Buy 900 treats").tap()
        sleep(1)
        snap("08-treat-store-purchasing")
        sleep(3)
        snap("09-treat-store-credited")

        app.buttons["Done"].tap()
        sleep(1)
        snap("10-shop-after-topup")
    }
}
