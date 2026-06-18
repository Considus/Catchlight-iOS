//
//  DefaultReminderWhenTests.swift
//  CatchlightCoreTests
//
//  The "Default when" reminder preference (owner 2026-06-18) resolves to a concrete
//  date when seeding the picker. The key invariant: every preset must land in the
//  FUTURE — a past default would open the picker in the past and the scheduler's
//  past-date guard would then silently refuse it. Also pins the "This evening" roll
//  (today 18:00, or tomorrow if already past).
//
//  iOS-only — `SettingsViewModel` lives in the app target.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

final class DefaultReminderWhenTests: XCTestCase {
    private typealias When = SettingsViewModel.DefaultReminderWhen

    /// A fixed instant on 2026-07-14 at the given hour (local calendar).
    private func at(_ hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 14; c.hour = hour; c.minute = 0
        return Calendar.current.date(from: c)!
    }

    func testEveryPresetIsInTheFuture() {
        let now = at(9)
        for option in When.allCases {
            XCTAssertGreaterThan(option.date(from: now), now,
                                 "\(option.rawValue) must resolve to a future date")
        }
    }

    func testThisEvening_beforeSix_isTodayAtSix() {
        let result = When.thisEvening.date(from: at(9))
        let parts = Calendar.current.dateComponents([.day, .hour], from: result)
        XCTAssertEqual(parts.day, 14)
        XCTAssertEqual(parts.hour, 18)
    }

    func testThisEvening_afterSix_rollsToTomorrow() {
        let result = When.thisEvening.date(from: at(20))   // 8pm — already past 6pm
        let parts = Calendar.current.dateComponents([.day, .hour], from: result)
        XCTAssertEqual(parts.day, 15, "after 6pm, This evening rolls to tomorrow")
        XCTAssertEqual(parts.hour, 18)
    }

    func testTomorrowMorning_isNextDayAtNine() {
        let result = When.tomorrowMorning.date(from: at(9))
        let parts = Calendar.current.dateComponents([.day, .hour], from: result)
        XCTAssertEqual(parts.day, 15)
        XCTAssertEqual(parts.hour, 9)
    }
}
#endif
