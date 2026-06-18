//
//  DefaultReminderHoursTests.swift
//  CatchlightCoreTests
//
//  The "Default timing (hrs)" reminder preference (owner 2026-06-18) resolves to
//  `now + N hours` when seeding the picker. Every option must land in the FUTURE — a
//  past default would open the picker in the past and the scheduler's past-date guard
//  would then silently refuse it.
//
//  iOS-only — `SettingsViewModel` lives in the app target.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

final class DefaultReminderHoursTests: XCTestCase {
    private typealias Hours = SettingsViewModel.DefaultReminderHours

    func testRawValuesAreTheHourCounts() {
        XCTAssertEqual(Hours.allCases.map(\.hours), [1, 6, 12, 24, 48])
    }

    func testEachOptionResolvesToNowPlusItsHours() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        for option in Hours.allCases {
            let expected = now.addingTimeInterval(TimeInterval(option.hours) * 3600)
            XCTAssertEqual(option.date(from: now), expected,
                           "\(option.rawValue)h must resolve to now + \(option.hours)h")
        }
    }

    func testEveryOptionIsInTheFuture() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        for option in Hours.allCases {
            XCTAssertGreaterThan(option.date(from: now), now)
        }
    }
}
#endif
