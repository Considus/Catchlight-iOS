//
//  SequenceFilterTests.swift
//  CatchlightCoreTests — filter-based Sequences (2026-06-10)
//
//  The pure matcher behind saved Sequences AND the Search surface (the same
//  predicate powers both, so they can never disagree). Calendar-sensitive
//  cases pin an explicit UTC calendar for determinism.
//

import XCTest
@testable import CatchlightCore

final class SequenceFilterTests: XCTestCase {

    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func take(_ body: String = "a thought",
                      task: Bool = false,
                      complete: Bool = false,
                      reminder: Bool = false,
                      reminderDate: Date = Date(timeIntervalSince1970: 2_000_000_000),
                      createdAt: String = "2026-06-05T09:00:00.000Z") -> Take {
        Take(createdAt: ISO8601.date(from: createdAt)!,
             blocks: task ? [.checkItem(body, isComplete: complete)] : [.textLine(body)],
             timeReminder: reminder
                ? TimeReminder(scheduledDate: reminderDate,
                               notificationIdentifier: "x")
                : nil)
    }

    func testEmptyFilter_matchesEverything_andReportsEmpty() {
        let f = SequenceFilter()
        XCTAssertTrue(f.isEmpty)
        XCTAssertTrue(f.matches(take(), calendar: utc))
        XCTAssertTrue(f.matches(take(task: true, complete: true, reminder: true), calendar: utc))
    }

    func testTextMatch_isCaseInsensitiveSubstring_sameAsStoreSearch() {
        let f = SequenceFilter(text: "DARK")
        XCTAssertTrue(f.matches(take("a darkroom session"), calendar: utc))
        XCTAssertFalse(f.matches(take("a bright morning"), calendar: utc))
        // Whitespace-only text imposes no constraint.
        XCTAssertTrue(SequenceFilter(text: "   ").isEmpty)
    }

    func testDimensionChips_individually() {
        XCTAssertTrue(SequenceFilter(requireTask: true).matches(take(task: true), calendar: utc))
        XCTAssertFalse(SequenceFilter(requireTask: true).matches(take(), calendar: utc))

        XCTAssertTrue(SequenceFilter(requireReminder: true).matches(take(reminder: true), calendar: utc))
        XCTAssertFalse(SequenceFilter(requireReminder: true).matches(take(), calendar: utc))

        // "Notes" = pure notes: no task, no reminder.
        XCTAssertTrue(SequenceFilter(requireNoteOnly: true).matches(take(), calendar: utc))
        XCTAssertFalse(SequenceFilter(requireNoteOnly: true).matches(take(task: true), calendar: utc))
        XCTAssertFalse(SequenceFilter(requireNoteOnly: true).matches(take(reminder: true), calendar: utc))

        // "Done" = completed TASKS only.
        XCTAssertTrue(SequenceFilter(requireCompleted: true).matches(take(task: true, complete: true), calendar: utc))
        XCTAssertFalse(SequenceFilter(requireCompleted: true).matches(take(task: true), calendar: utc))
        XCTAssertFalse(SequenceFilter(requireCompleted: true).matches(take(), calendar: utc))
    }

    // Dock redesign (2026-06-10): "Expired" modifier on the Reminders toggle.
    func testRequireExpiredReminder_matchesOnlyPastDatedReminders() {
        let now = ISO8601.date(from: "2026-06-10T12:00:00.000Z")!
        let past = ISO8601.date(from: "2026-06-09T12:00:00.000Z")!
        let future = ISO8601.date(from: "2026-06-11T12:00:00.000Z")!
        let f = SequenceFilter(requireExpiredReminder: true)

        // Expired: scheduled date already passed relative to `now`.
        XCTAssertTrue(f.matches(take(reminder: true, reminderDate: past), calendar: utc, now: now))
        // A future reminder is not expired.
        XCTAssertFalse(f.matches(take(reminder: true, reminderDate: future), calendar: utc, now: now))
        // A Take without any reminder can never satisfy the constraint.
        XCTAssertFalse(f.matches(take(), calendar: utc, now: now))
        // The constraint counts toward isEmpty.
        XCTAssertFalse(f.isEmpty)
        XCTAssertTrue(SequenceFilter().isEmpty)
    }

    /// Owner's exact case (2026-06-10): Tasks + Reminders both toggled on →
    /// only Takes that are BOTH a task AND carry a reminder (AND semantics).
    func testTaskAndReminder_andComposition_requiresBoth() {
        let f = SequenceFilter(requireTask: true, requireReminder: true)
        XCTAssertTrue(f.matches(take(task: true, reminder: true), calendar: utc))
        XCTAssertFalse(f.matches(take(task: true), calendar: utc))            // task only
        XCTAssertFalse(f.matches(take(reminder: true), calendar: utc))        // reminder only
        XCTAssertFalse(f.matches(take(), calendar: utc))                      // neither
    }

    func testMonths_orWithinDimension_andWithEverythingElse() {
        let june = take("june task", task: true, createdAt: "2026-06-05T09:00:00.000Z")
        let may = take("may task", task: true, createdAt: "2026-05-05T09:00:00.000Z")
        let april = take("april note", createdAt: "2026-04-05T09:00:00.000Z")

        let mayOrJuneTasks = SequenceFilter(requireTask: true, months: ["2026-05", "2026-06"])
        XCTAssertTrue(mayOrJuneTasks.matches(june, calendar: utc))
        XCTAssertTrue(mayOrJuneTasks.matches(may, calendar: utc))
        XCTAssertFalse(mayOrJuneTasks.matches(april, calendar: utc))

        // Text AND month AND chip compose.
        let composed = SequenceFilter(text: "june", requireTask: true, months: ["2026-06"])
        XCTAssertTrue(composed.matches(june, calendar: utc))
        XCTAssertFalse(composed.matches(may, calendar: utc))
    }

    func testMonthKey_usesSuppliedCalendar() {
        // 2026-06-30T23:30Z is already July 1st in UTC+10.
        let lateJune = ISO8601.date(from: "2026-06-30T23:30:00.000Z")!
        XCTAssertEqual(SequenceFilter.monthKey(for: lateJune, calendar: utc), "2026-06")
        var sydney = Calendar(identifier: .gregorian)
        sydney.timeZone = TimeZone(identifier: "Australia/Sydney")!
        XCTAssertEqual(SequenceFilter.monthKey(for: lateJune, calendar: sydney), "2026-07")
    }

    func testCodable_roundTrip_andTolerantDecodingDefaults() throws {
        let f = SequenceFilter(text: "x", requireTask: true, requireCompleted: true, months: ["2026-06"])
        let decoded = try PlatformJSON.decode(SequenceFilter.self, from: try PlatformJSON.encode(f))
        XCTAssertEqual(decoded, f)

        // A bare object (future client, older schema) decodes to the empty filter.
        let bare = try PlatformJSON.decode(SequenceFilter.self, from: Data("{}".utf8))
        XCTAssertTrue(bare.isEmpty)
    }

    func testSummary_buildsDefaultSequenceName() {
        let f = SequenceFilter(text: "darkroom", requireTask: true, months: ["2026-06"])
        let name = f.summary(monthLabel: { _ in "June 2026" })
        XCTAssertEqual(name, "darkroom · Tasks · June 2026")
        XCTAssertEqual(SequenceFilter().summary(monthLabel: { $0 }), "Everything")
    }
}
