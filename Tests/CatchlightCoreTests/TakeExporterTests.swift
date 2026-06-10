//
//  TakeExporterTests.swift
//  CatchlightCoreTests — Task 6.22
//
//  Pins the export format defined in `App_Store_Connect_Decisions_v1.0.md §5`.
//  These tests are deliberately literal — they string-compare the full payload
//  rather than parsing it, because downstream importers will rely on the exact
//  byte layout (frontmatter delimiters, the `· ✓ Complete` separator, the
//  bell glyph, blank-line spacing). Any change here is a format change and
//  must trace back to an explicit decision update.
//

import XCTest
@testable import CatchlightCore

final class TakeExporterTests: XCTestCase {

    // MARK: - Deterministic timestamps

    /// 2026-06-09T14:32:00Z — the exact moment in the spec example.
    private let exportedAt = makeUTC(year: 2026, month: 6, day: 9,
                                     hour: 14, minute: 32, second: 0)

    private static func makeUTC(year: Int, month: Int, day: Int,
                                hour: Int = 0, minute: Int = 0, second: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = second
        c.timeZone = TimeZone(secondsFromGMT: 0)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: c)!
    }

    // MARK: - Empty export

    func testExport_emptyArray_writesOnlyFrontmatter() {
        let out = TakeExporter.export([], exportedAt: exportedAt)
        let expected = """
        ---
        exported: 2026-06-09T14:32:00Z
        takes: 0
        ---

        """
        XCTAssertEqual(out, expected)
    }

    // MARK: - Single Take per type

    func testExport_singleNote_rendersNoteHeading() {
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 14)
        let take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        bodyText: "Buy film for the weekend shoot",
                        isNote: true)
        let out = TakeExporter.export([take], exportedAt: exportedAt)
        let expected = """
        ---
        exported: 2026-06-09T14:32:00Z
        takes: 1
        ---

        ## Note — 2026-05-14
        Buy film for the weekend shoot

        """
        XCTAssertEqual(out, expected)
    }

    func testExport_completedTask_appendsCompleteMarker() {
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 15)
        let take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        bodyText: "Call the framer back",
                        isNote: true, isTask: true, isComplete: true)
        let out = TakeExporter.export([take], exportedAt: exportedAt)
        XCTAssertTrue(out.contains("## Task — 2026-05-15 · ✓ Complete"))
        XCTAssertTrue(out.contains("Call the framer back"))
    }

    func testExport_incompleteTask_omitsCompleteMarker() {
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 15)
        let take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        bodyText: "Call the framer back",
                        isNote: true, isTask: true, isComplete: false)
        let out = TakeExporter.export([take], exportedAt: exportedAt)
        XCTAssertTrue(out.contains("## Task — 2026-05-15"))
        XCTAssertFalse(out.contains("✓ Complete"))
    }

    func testExport_reminderWithDate_appendsBellAndStamp() {
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 16)
        let scheduledAt = Self.makeUTC(year: 2026, month: 5, day: 20, hour: 9, minute: 0)
        var take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        bodyText: "Pick up prints",
                        isNote: true)
        take.timeReminder = TimeReminder(scheduledDate: scheduledAt,
                                         notificationIdentifier: take.id.uuidString)
        let out = TakeExporter.export([take], exportedAt: exportedAt)
        XCTAssertTrue(out.contains("## Reminder — 2026-05-16 · 🔔 2026-05-20 09:00"),
                      "Got: \(out)")
        XCTAssertTrue(out.contains("Pick up prints"))
    }

    func testExport_takeWithoutReminder_neverEmitsBellGlyph() {
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 14)
        let take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        bodyText: "no reminder here", isNote: true)
        let out = TakeExporter.export([take], exportedAt: exportedAt)
        XCTAssertFalse(out.contains("🔔"))
    }

    // MARK: - Ordering

    func testExport_multipleTakes_sortedByCreatedAtAscending() {
        let t1 = Take(createdAt: Self.makeUTC(year: 2026, month: 5, day: 14),
                      modifiedAt: Self.makeUTC(year: 2026, month: 5, day: 14),
                      bodyText: "first", isNote: true)
        let t2 = Take(createdAt: Self.makeUTC(year: 2026, month: 5, day: 15),
                      modifiedAt: Self.makeUTC(year: 2026, month: 5, day: 15),
                      bodyText: "second", isNote: true)
        let t3 = Take(createdAt: Self.makeUTC(year: 2026, month: 5, day: 16),
                      modifiedAt: Self.makeUTC(year: 2026, month: 5, day: 16),
                      bodyText: "third", isNote: true)
        // Feed in reverse order — exporter must re-sort.
        let out = TakeExporter.export([t3, t1, t2], exportedAt: exportedAt)
        guard let firstRange = out.range(of: "first"),
              let secondRange = out.range(of: "second"),
              let thirdRange = out.range(of: "third") else {
            return XCTFail("All bodies should appear in output: \(out)")
        }
        XCTAssertTrue(firstRange.lowerBound < secondRange.lowerBound)
        XCTAssertTrue(secondRange.lowerBound < thirdRange.lowerBound)
    }

    // MARK: - Spacing

    func testExport_multipleTakes_oneBlankLineBetween() {
        let t1 = Take(createdAt: Self.makeUTC(year: 2026, month: 5, day: 14),
                      modifiedAt: Self.makeUTC(year: 2026, month: 5, day: 14),
                      bodyText: "first", isNote: true)
        let t2 = Take(createdAt: Self.makeUTC(year: 2026, month: 5, day: 15),
                      modifiedAt: Self.makeUTC(year: 2026, month: 5, day: 15),
                      bodyText: "second", isNote: true)
        let out = TakeExporter.export([t1, t2], exportedAt: exportedAt)
        // Body of first Take ends with "first\n", then exactly one blank line
        // ("\n"), then the next H2 begins. No double blanks anywhere.
        XCTAssertTrue(out.contains("first\n\n## Note"),
                      "Expected exactly one blank line between Takes. Got: \(out)")
        XCTAssertFalse(out.contains("\n\n\n"),
                       "Found a triple-newline (extra blank). Got: \(out)")
    }

    func testExport_takeCountReflectsActualNumberOfTakes() {
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 14)
        let takes = (0..<3).map { i in
            Take(createdAt: createdAt, modifiedAt: createdAt,
                 bodyText: "t\(i)", isNote: true)
        }
        let out = TakeExporter.export(takes, exportedAt: exportedAt)
        XCTAssertTrue(out.contains("takes: 3\n"))
    }

    // MARK: - Special characters

    func testExport_bodyWithQuotesAndBackticks_passedThroughVerbatim() {
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 14)
        let take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        bodyText: #"She said "go" and we ran. `code` and 'quotes'"#,
                        isNote: true)
        let out = TakeExporter.export([take], exportedAt: exportedAt)
        XCTAssertTrue(out.contains(#"She said "go" and we ran. `code` and 'quotes'"#))
    }

    func testExport_bodyWithNewlines_preservesMultiLineBody() {
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 14)
        let take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        bodyText: "line one\nline two\nline three",
                        isNote: true)
        let out = TakeExporter.export([take], exportedAt: exportedAt)
        XCTAssertTrue(out.contains("line one\nline two\nline three"))
    }

    func testExport_bodyWithMarkdownChars_notEscaped() {
        // Plain Markdown source — we deliberately do not escape user content
        // since the file IS Markdown; a body that contains "# heading" or "*"
        // round-trips intact for the user when re-imported into a Markdown app.
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 14)
        let take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        bodyText: "# user heading\n* item",
                        isNote: true)
        let out = TakeExporter.export([take], exportedAt: exportedAt)
        XCTAssertTrue(out.contains("# user heading\n* item"))
    }

    // MARK: - Frontmatter

    func testExport_frontmatterUsesISO8601UTCWithoutFractionalSeconds() {
        let out = TakeExporter.export([], exportedAt: exportedAt)
        XCTAssertTrue(out.hasPrefix("---\nexported: 2026-06-09T14:32:00Z\n"))
    }

    // MARK: - Heading precedence

    func testHeading_takeWithBothReminderAndTask_prefersReminder() {
        // Specification ambiguity: a Take may have both isTask and a reminder.
        // Decision: most specific qualifier wins for the H2 — Reminder.
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 14)
        let scheduledAt = Self.makeUTC(year: 2026, month: 5, day: 20, hour: 9, minute: 0)
        var take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        bodyText: "x", isNote: true, isTask: true, isComplete: true)
        take.timeReminder = TimeReminder(scheduledDate: scheduledAt,
                                         notificationIdentifier: take.id.uuidString)
        XCTAssertEqual(TakeExporter.heading(for: take),
                       "Reminder — 2026-05-14 · 🔔 2026-05-20 09:00")
    }

    // MARK: - Filename

    func testSuggestedFilename_isCatchlightDateMd() {
        XCTAssertEqual(TakeExporter.suggestedFilename(exportedAt: exportedAt),
                       "catchlight-2026-06-09.md")
    }
}
