//
//  GreetingTests.swift
//  DogHouseTests
//

import Foundation
import Testing
@testable import DogHouse

struct GreetingTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: hour))!
    }

    @Test("Salutation follows the hour")
    func salutation() {
        #expect(HomeView.salutation(at: date(hour: 5), calendar: calendar) == "Good morning")
        #expect(HomeView.salutation(at: date(hour: 11), calendar: calendar) == "Good morning")
        #expect(HomeView.salutation(at: date(hour: 12), calendar: calendar) == "Good afternoon")
        #expect(HomeView.salutation(at: date(hour: 17), calendar: calendar) == "Good evening")
        #expect(HomeView.salutation(at: date(hour: 22), calendar: calendar) == "Hey")
        #expect(HomeView.salutation(at: date(hour: 2), calendar: calendar) == "Hey")
    }
}
