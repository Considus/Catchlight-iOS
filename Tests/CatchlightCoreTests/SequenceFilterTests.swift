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
                      createdAt: String = "2026-06-05T09:00:00.000Z") -> Take {
        Take(createdAt: ISO8601.date(from: createdAt)!,
             bodyText: body,
             isTask: task,
             isComplete: complete,
             timeReminder: reminder
                ? TimeReminder(scheduledDate: Date(timeIntervalSince1970: 2_000_000_000),
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
