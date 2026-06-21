//
//  RecurrenceClampTests.swift
//  CatchlightCoreTests — month-end / leap-day recurrence safety (owner 2026-06-21)
//
//  A `monthly` reminder anchored on the 29th–31st, or an `annually` one on 29 Feb,
//  must NOT skip the months/years that lack that day — it CLAMPS to the last valid day
//  (matching Apple Reminders). These tests pin that, plus the unchanged behaviour for
//  ordinary anchor days and the cadences that never need clamping.
//

import XCTest
@testable import CatchlightCore

final class RecurrenceClampTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func reminder(_ rec: TimeReminder.Recurrence, at iso: String) -> TimeReminder {
        TimeReminder(scheduledDate: ISO8601.date(from: iso)!,
                     notificationIdentifier: "x",
                     recurrence: rec)
    }

    private func day(_ date: Date) -> Int { cal.component(.day, from: date) }

    // MARK: monthly clamp

    func testMonthly_on31st_clampsToShortMonths_neverSkips() {
        // Anchored 31 Jan 2026, 09:00. Stepping month by month must yield a fire in EVERY
        // month, clamped to each month's last day — never skipping Feb/Apr/Jun/Sep/Nov.
        let r = reminder(.monthly, at: "2026-01-31T09:00:00.000Z")
        var cursor = ISO8601.date(from: "2026-01-31T09:00:01.000Z")!   // just after the anchor
        let expectedDays = [28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]   // Feb…Dec 2026
        var seenMonths: [Int] = []
        for expectedDay in expectedDays {
            let next = r.nextOccurrence(after: cursor, calendar: cal)
            XCTAssertEqual(day(next), expectedDay, "wrong clamped day for \(next)")
            seenMonths.append(cal.component(.month, from: next))
            XCTAssertEqual(cal.component(.hour, from: next), 9)
            cursor = next
        }
        // Consecutive months 2…12, none skipped.
        XCTAssertEqual(seenMonths, Array(2...12))
    }

    func testMonthly_on30th_clampsFebruaryOnly() {
        let r = reminder(.monthly, at: "2026-01-30T08:30:00.000Z")
        let afterJan = ISO8601.date(from: "2026-01-30T09:00:00.000Z")!
        let feb = r.nextOccurrence(after: afterJan, calendar: cal)
        XCTAssertEqual(day(feb), 28)                      // Feb 2026 has no 30th → clamp
        XCTAssertEqual(cal.component(.month, from: feb), 2)
        let mar = r.nextOccurrence(after: feb, calendar: cal)
        XCTAssertEqual(day(mar), 30)                      // March restores the 30th
    }

    func testMonthly_ordinaryDay_isUnchanged() {
        // Day 16 exists in every month — clamp is a no-op, identical to "+1 month".
        let r = reminder(.monthly, at: "2026-06-16T09:00:00.000Z")
        let after = ISO8601.date(from: "2026-06-16T09:00:30.000Z")!
        let next = r.nextOccurrence(after: after, calendar: cal)
        XCTAssertEqual(next, cal.date(byAdding: .month, value: 1, to: r.scheduledDate))
    }

    // MARK: annual / leap-day clamp

    func testAnnually_onFeb29_clampsToFeb28InCommonYears() {
        // Anchored 29 Feb 2024 (leap). Next fires must be 28 Feb 2025/2026/2027, then
        // 29 Feb 2028 again — never skipping three years waiting for the next leap.
        let r = reminder(.annually, at: "2024-02-29T07:00:00.000Z")
        var cursor = ISO8601.date(from: "2024-02-29T07:00:01.000Z")!
        for expected in ["2025-02-28", "2026-02-28", "2027-02-28", "2028-02-29"] {
            let next = r.nextOccurrence(after: cursor, calendar: cal)
            let comps = cal.dateComponents([.year, .month, .day], from: next)
            let stamp = String(format: "%04d-%02d-%02d", comps.year!, comps.month!, comps.day!)
            XCTAssertEqual(stamp, expected)
            XCTAssertEqual(cal.component(.hour, from: next), 7)
            cursor = next
        }
    }

    func testAnnually_ordinaryDate_isUnchanged() {
        let r = reminder(.annually, at: "2026-06-16T09:00:00.000Z")
        let after = ISO8601.date(from: "2026-06-16T09:00:30.000Z")!
        let next = r.nextOccurrence(after: after, calendar: cal)
        XCTAssertEqual(next, cal.date(byAdding: .year, value: 1, to: r.scheduledDate))
    }

    // MARK: isOverdue single source

    func testIsOverdue_pastUndoneOneShot_isOverdue() {
        let r = reminder(.none, at: "2026-06-09T12:00:00.000Z")
        XCTAssertTrue(r.isOverdue(now: ISO8601.date(from: "2026-06-10T12:00:00.000Z")!))
    }

    func testIsOverdue_futureOrDoneOrRepeating_isNotOverdue() {
        let now = ISO8601.date(from: "2026-06-10T12:00:00.000Z")!
        // Future one-shot.
        XCTAssertFalse(reminder(.none, at: "2026-06-11T12:00:00.000Z").isOverdue(now: now))
        // Past but done.
        var done = reminder(.none, at: "2026-06-09T12:00:00.000Z"); done.isDone = true
        XCTAssertFalse(done.isOverdue(now: now))
        // Repeating, anchor in the past — never overdue.
        XCTAssertFalse(reminder(.daily, at: "2026-06-09T12:00:00.000Z").isOverdue(now: now))
        XCTAssertFalse(reminder(.monthly, at: "2026-05-31T12:00:00.000Z").isOverdue(now: now))
    }
}
