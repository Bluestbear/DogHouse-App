//
//  LegalTests.swift
//  DogHouseTests
//
//  The pairing link is the one growth feature at launch; a parser that
//  silently drops a code sends the partner back to typing it.
//

import XCTest
@testable import DogHouse

final class LegalTests: XCTestCase {
    func testUniversalLinkYieldsCode() {
        let url = URL(string: "https://doghouse-5e80e.web.app/pair/ab7k9x")!
        XCTAssertEqual(Legal.pairingCode(from: url), "AB7K9X")
    }

    func testSchemeFallbackYieldsCode() {
        let url = URL(string: "doghouse://pair/QW3RTY")!
        XCTAssertEqual(Legal.pairingCode(from: url), "QW3RTY")
    }

    func testRoundTripThroughPairingLink() {
        XCTAssertEqual(Legal.pairingCode(from: Legal.pairingLink(code: "ZX9V8B")), "ZX9V8B")
    }

    func testOtherURLsAreIgnored() {
        XCTAssertNil(Legal.pairingCode(from: URL(string: "https://doghouse-5e80e.web.app/privacy.html")!))
        XCTAssertNil(Legal.pairingCode(from: URL(string: "https://example.com/pair/ABCDEF")!))
        XCTAssertNil(Legal.pairingCode(from: URL(string: "https://doghouse-5e80e.web.app/pair/TOOSHORT!")!))
        XCTAssertNil(Legal.pairingCode(from: URL(string: "com.googleusercontent.apps.x:/oauth2redirect")!))
    }
}
