//
//  TimeReminderWeekdayValidationTests.swift
//  CatchlightCoreTests — 2026-07-01 mid-point review remediation
//
//  Out-of-range weekday numbers (Calendar weekdays are 1 = Sunday … 7 =
//  Saturday) previously made `nextWeekly` yield no candidates and fall back to
//  the PAST anchor — so `advanceRecurringOccurrence` never advanced and "mark
//  done" could never complete the reminder. Both inits now drop invalid values,
//  and weekly matching preserves the anchor's SECONDS like the other cadences.
//

import XCTest
@testable import CatchlightCore

final class TimeReminderWeekdayValidationTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testInit_dropsOutOfRangeWeekdays() {
        let r = TimeReminder(scheduledDate: Date(timeIntervalSince1970: 1_780_000_000),
                             notificationIdentifier: "t",
                             recurrence: .weekly,
                             weekdays: [0, 2, 4, 8, -1])
        XCTAssertEqual(r.weekdays, [2, 4])
    }

    func testDecode_dropsOutOfRangeWeekdays() throws {
        // Encode a valid reminder, splice an invalid weekday set into the JSON,
        // and decode — the decode path must filter exactly like the init.
        let valid = TimeReminder(scheduledDate: Date(timeIntervalSince1970: 1_780_000_000),
                                 notificationIdentifier: "t",
                                 recurrence: .weekly,
                                 weekdays: [3])
        let data = try PlatformJSON.encode(valid)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["weekdays"] = [0, 3, 9]
        let spliced = try JSONSerialization.data(withJSONObject: json)
        let decoded = try PlatformJSON.decode(TimeReminder.self, from: spliced)
        XCTAssertEqual(decoded.weekdays, [3])
    }

    /// An entirely-invalid set behaves like the empty set (anchor's own
    /// weekday) — critically, `nextOccurrence` must return a FUTURE date, not
    /// the past anchor, so a recurring reminder can always advance.
    func testNextOccurrence_invalidSetStillAdvances() throws {
        let anchor = try XCTUnwrap(ISO8601.date(from: "2026-06-01T09:00:00.000Z"))  // a Monday
        let r = TimeReminder(scheduledDate: anchor,
                             notificationIdentifier: "t",
                             recurrence: .weekly,
                             weekdays: [0])          // invalid → filtered to empty
        let now = try XCTUnwrap(ISO8601.date(from: "2026-06-10T12:00:00.000Z"))
        let next = r.nextOccurrence(after: now, calendar: utc)
        XCTAssertGreaterThan(next, now, "a recurring reminder must always advance")
        XCTAssertEqual(utc.component(.weekday, from: next),
                       utc.component(.weekday, from: anchor))
    }

    /// Weekly matching preserves the anchor's seconds — previously hour+minute
    /// only, which silently zeroed seconds while monthly/annual preserved them.
    func testNextWeekly_preservesAnchorSeconds() throws {
        let anchor = try XCTUnwrap(ISO8601.date(from: "2026-06-01T09:15:30.000Z"))
        let r = TimeReminder(scheduledDate: anchor,
                             notificationIdentifier: "t",
                             recurrence: .weekly,
                             weekdays: [3])          // Tuesdays
        let now = try XCTUnwrap(ISO8601.date(from: "2026-06-10T12:00:00.000Z"))
        let next = r.nextOccurrence(after: now, calendar: utc)
        let comps = utc.dateComponents([.weekday, .hour, .minute, .second], from: next)
        XCTAssertEqual(comps.weekday, 3)
        XCTAssertEqual(comps.hour, 9)
        XCTAssertEqual(comps.minute, 15)
        XCTAssertEqual(comps.second, 30)
    }
}
