//
//  WeekdayRecurrenceTests.swift
//  CatchlightCoreTests — weekly reminders over a weekday SET (owner 2026-06-23)
//
//  A WEEKLY reminder can fire on several weekdays at the anchor's time-of-day: the
//  "Every weekday" / "Weekends" presets and a custom multi-select all map to a
//  `weekdays` set (Calendar weekday numbers, 1 = Sun … 7 = Sat). These pin that the
//  next occurrence is the EARLIEST match across the set, that an EMPTY set still
//  behaves exactly like the single anchor-weekday case (back-compat), and that the
//  field survives Codable — including legacy payloads written before it existed.
//

import XCTest
@testable import CatchlightCore

final class WeekdayRecurrenceTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func weekly(_ weekdays: Set<Int>, at iso: String) -> TimeReminder {
        TimeReminder(scheduledDate: ISO8601.date(from: iso)!,
                     notificationIdentifier: "x",
                     recurrence: .weekly,
                     weekdays: weekdays)
    }

    /// Walk `count` occurrences from just after the anchor and return each as "MM-dd HH".
    private func walk(_ r: TimeReminder, fromJustAfter iso: String, count: Int) -> [String] {
        var cursor = ISO8601.date(from: iso)!.addingTimeInterval(1)
        var out: [String] = []
        for _ in 0..<count {
            let next = r.nextOccurrence(after: cursor, calendar: cal)
            let c = cal.dateComponents([.month, .day, .hour], from: next)
            out.append(String(format: "%02d-%02d %02d", c.month!, c.day!, c.hour!))
            cursor = next
        }
        return out
    }

    // MARK: empty set == single anchor weekday (back-compat)

    func testEmptySet_firesOnAnchorWeekday_weekly() {
        // Anchored Monday 15 Jun 2026 09:00; with no weekday set it stays a weekly-Monday.
        let r = weekly([], at: "2026-06-15T09:00:00.000Z")
        XCTAssertEqual(walk(r, fromJustAfter: "2026-06-15T09:00:00.000Z", count: 3),
                       ["06-22 09", "06-29 09", "07-06 09"])   // every following Monday
    }

    func testEmptySet_matchesLegacyWeekdayComponentsMatching() {
        // The empty-set path must be byte-identical to the old single-weekday calendar match,
        // so existing weekly reminders are wholly unaffected.
        let r = weekly([], at: "2026-06-19T09:00:00.000Z")    // Friday
        let after = ISO8601.date(from: "2026-06-20T00:00:00.000Z")!
        var comps = DateComponents()
        comps.weekday = cal.component(.weekday, from: r.scheduledDate)
        comps.hour = 9; comps.minute = 0
        let expected = cal.nextDate(after: after, matching: comps,
                                    matchingPolicy: .nextTimePreservingSmallerComponents)
        XCTAssertEqual(r.nextOccurrence(after: after, calendar: cal), expected)
    }

    // MARK: presets

    func testEveryWeekday_skipsTheWeekend() {
        // Anchored Friday 19 Jun 2026 09:00. Mon–Fri set ⇒ next is Monday, never Sat/Sun.
        let r = weekly(TimeReminder.weekdaySet, at: "2026-06-19T09:00:00.000Z")
        XCTAssertEqual(walk(r, fromJustAfter: "2026-06-19T09:00:00.000Z", count: 6),
                       ["06-22 09", "06-23 09", "06-24 09", "06-25 09", "06-26 09", "06-29 09"])
    }

    func testWeekends_onlySaturdayAndSunday() {
        // Anchored Saturday 20 Jun 2026 09:00. {Sat,Sun} ⇒ Sun, then next weekend, …
        let r = weekly(TimeReminder.weekendSet, at: "2026-06-20T09:00:00.000Z")
        XCTAssertEqual(walk(r, fromJustAfter: "2026-06-20T09:00:00.000Z", count: 4),
                       ["06-21 09", "06-27 09", "06-28 09", "07-04 09"])
    }

    func testCustomMonWedFri_picksEarliestInSet() {
        // Anchored Monday 15 Jun 2026 09:00, {Mon,Wed,Fri} = {2,4,6}.
        let r = weekly([2, 4, 6], at: "2026-06-15T09:00:00.000Z")
        XCTAssertEqual(walk(r, fromJustAfter: "2026-06-15T09:00:00.000Z", count: 5),
                       ["06-17 09", "06-19 09", "06-22 09", "06-24 09", "06-26 09"])
    }

    func testWeekdaySet_preservesAnchorTimeOfDay() {
        let r = weekly(TimeReminder.weekdaySet, at: "2026-06-19T14:30:00.000Z")
        let next = r.nextOccurrence(after: ISO8601.date(from: "2026-06-19T14:30:01.000Z")!, calendar: cal)
        XCTAssertEqual(cal.component(.hour, from: next), 14)
        XCTAssertEqual(cal.component(.minute, from: next), 30)
    }

    // MARK: effectiveNextDue uses the set

    func testEffectiveNextDue_recurringPastAnchor_advancesAcrossSet() {
        let r = weekly(TimeReminder.weekdaySet, at: "2026-06-19T09:00:00.000Z")   // Fri anchor
        let now = ISO8601.date(from: "2026-06-22T12:00:00.000Z")!                 // Mon lunchtime
        let due = r.effectiveNextDue(now: now, calendar: cal)
        let c = cal.dateComponents([.month, .day], from: due)
        XCTAssertEqual([c.month!, c.day!], [6, 23])   // next weekday occurrence: Tue 23 Jun
    }

    // MARK: Codable

    func testCodable_roundTripsWeekdays() throws {
        let r = weekly([2, 4, 6], at: "2026-06-15T09:00:00.000Z")
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(TimeReminder.self, from: data)
        XCTAssertEqual(back.weekdays, [2, 4, 6])
        XCTAssertEqual(back, r)
    }

    func testCodable_legacyPayloadWithoutWeekdays_decodesEmpty() throws {
        // Simulate a payload written before `weekdays` existed: encode, drop the key, decode.
        let r = weekly([2, 4, 6], at: "2026-06-15T09:00:00.000Z")
        var json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(r)) as! [String: Any]
        json.removeValue(forKey: "weekdays")
        let stripped = try JSONSerialization.data(withJSONObject: json)
        let back = try JSONDecoder().decode(TimeReminder.self, from: stripped)
        XCTAssertEqual(back.weekdays, [])   // decodeIfPresent default — weekly-on-anchor-day
    }
}
