//
//  ReminderQuickSetPresetTests.swift
//  CatchlightAppTests — 2026-07-04 testability follow-up to the mid-point remediation
//
//  Pins the reminder quick-set preset date maths, notably the "This weekend
//  includes the weekend you're in" edge fixed in PR #102: strictly-after weekday
//  matching used to skip a Saturday/Sunday tap to NEXT Saturday. `Preset` was
//  `private` inside `ReminderPickerSheet`; it's now internal purely so this pure
//  maths is testable (the enum is not referenced elsewhere).
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight
@testable import CatchlightCore

final class ReminderQuickSetPresetTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func make(_ y: Int, _ mo: Int, _ d: Int, _ h: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: 0))!
    }

    /// On a WEEKDAY, "This weekend" is the coming Saturday at the all-day fire hour.
    func testThisWeekend_onAWeekday_isComingSaturday() {
        let now = make(2026, 7, 1, 10)   // a Wednesday
        XCTAssertEqual(utc.component(.weekday, from: now), 4, "fixture must be a Wednesday")

        let result = ReminderPickerSheet.Preset.thisWeekend.date(now: now, calendar: utc)

        XCTAssertEqual(utc.component(.weekday, from: result), 7, "Saturday")
        XCTAssertEqual(utc.component(.hour, from: result), ReminderScheduler.allDayFireHour)
        XCTAssertEqual(utc.component(.day, from: result), 4, "the coming Saturday, 4 Jul 2026")
        XCTAssertGreaterThan(result, now)
    }

    /// The regression: on a Saturday morning (before the fire hour) "This weekend"
    /// is THAT Saturday — it must not skip to next week (the strictly-after bug).
    func testThisWeekend_onSaturdayMorning_isSameWeekend() {
        let now = make(2026, 7, 4, 7)    // Saturday 07:00, before the 09:00 fire hour
        XCTAssertEqual(utc.component(.weekday, from: now), 7, "fixture must be a Saturday")

        let result = ReminderPickerSheet.Preset.thisWeekend.date(now: now, calendar: utc)

        XCTAssertEqual(utc.component(.day, from: result), 4, "the same Saturday, not next week")
        XCTAssertEqual(utc.component(.hour, from: result), ReminderScheduler.allDayFireHour)
        XCTAssertGreaterThan(result, now)
    }

    /// "Tomorrow" lands on the next day at the fire hour.
    func testTomorrow_isNextDayAtFireHour() {
        let now = make(2026, 7, 1, 15)
        let result = ReminderPickerSheet.Preset.tomorrow.date(now: now, calendar: utc)
        XCTAssertEqual(utc.component(.day, from: result), 2)
        XCTAssertEqual(utc.component(.hour, from: result), ReminderScheduler.allDayFireHour)
    }
}
#endif
