//
//  TakeExporterTests.swift
//  CatchlightCoreTests — Task 6.22 / D-035
//
//  Pins the export format defined in `App_Store_Connect_Decisions_v1.0.md §5`.
//  These tests are deliberately literal — they string-compare the full payload
//  rather than parsing it, because downstream importers will rely on the exact
//  byte layout (frontmatter delimiters, the `· ✓ Complete` separator, the
//  bell glyph, blank-line spacing). Any change here is a format change and
//  must trace back to an explicit decision update.
//
//  Under D-035 the body is rendered from `blocks`: prose lines as text, check
//  items as `- [ ]` / `- [x]`.
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
                        blocks: [.textLine("Buy film for the weekend shoot")],
                        isNote: true)
        let out = TakeExporter.export([take], exportedAt: exportedAt)
        // The VISIBLE Markdown is byte-exact and unchanged; the lossless data block
        // (D-088) follows it, so assert the human portion as a prefix.
        let expectedVisible = """
        ---
        exported: 2026-06-09T14:32:00Z
        takes: 1
        ---

        ## Note — 2026-05-14
        Buy film for the weekend shoot

        """
        XCTAssertTrue(out.hasPrefix(expectedVisible), "Got: \(out)")
        XCTAssertTrue(out.contains("<!-- catchlight:data"), "Markdown export carries the data block")
        XCTAssertTrue(out.hasSuffix("-->\n"))
    }

    func testExport_completedTask_rendersCheckMarkerAndHeading() {
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 15)
        let take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        blocks: [.checkItem("Call the framer back", isComplete: true)],
                        isNote: true)
        let out = TakeExporter.export([take], exportedAt: exportedAt)
        XCTAssertTrue(out.contains("## Task — 2026-05-15 · ✓ Complete"))
        XCTAssertTrue(out.contains("- [x] Call the framer back"))
    }

    func testExport_incompleteTask_omitsCompleteMarkerAndRendersOpenBox() {
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 15)
        let take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        blocks: [.checkItem("Call the framer back", isComplete: false)],
                        isNote: true)
        let out = TakeExporter.export([take], exportedAt: exportedAt)
        XCTAssertTrue(out.contains("## Task — 2026-05-15"))
        XCTAssertFalse(out.contains("✓ Complete"))
        XCTAssertTrue(out.contains("- [ ] Call the framer back"))
    }

    func testExport_interleavedBlocks_renderInOrder() {
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 15)
        let take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        blocks: [.textLine("Packing list"),
                                 .checkItem("passport", isComplete: true),
                                 .checkItem("charger"),
                                 .textLine("buy at airport:"),
                                 .checkItem("water")],
                        isNote: true)
        let out = TakeExporter.export([take], exportedAt: exportedAt)
        XCTAssertTrue(out.contains("""
        Packing list
        - [x] passport
        - [ ] charger
        buy at airport:
        - [ ] water
        """), "Got: \(out)")
    }

    func testExport_reminderWithDate_appendsBellAndStamp() {
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 16)
        let scheduledAt = Self.makeUTC(year: 2026, month: 5, day: 20, hour: 9, minute: 0)
        var take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        blocks: [.textLine("Pick up prints")],
                        isNote: true)
        take.timeReminder = TimeReminder(scheduledDate: scheduledAt,
                                         notificationIdentifier: take.id.uuidString)
        let out = TakeExporter.export([take], exportedAt: exportedAt,
                                      timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertTrue(out.contains("## Reminder — 2026-05-16 · 🔔 2026-05-20 09:00"),
                      "Got: \(out)")
        XCTAssertTrue(out.contains("Pick up prints"))
    }

    func testExport_takeWithoutReminder_neverEmitsBellGlyph() {
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 14)
        let take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        blocks: [.textLine("no reminder here")], isNote: true)
        let out = TakeExporter.export([take], exportedAt: exportedAt)
        XCTAssertFalse(out.contains("🔔"))
    }

    // MARK: - Ordering

    func testExport_multipleTakes_sortedByCreatedAtAscending() {
        let t1 = Take(createdAt: Self.makeUTC(year: 2026, month: 5, day: 14),
                      modifiedAt: Self.makeUTC(year: 2026, month: 5, day: 14),
                      blocks: [.textLine("first")], isNote: true)
        let t2 = Take(createdAt: Self.makeUTC(year: 2026, month: 5, day: 15),
                      modifiedAt: Self.makeUTC(year: 2026, month: 5, day: 15),
                      blocks: [.textLine("second")], isNote: true)
        let t3 = Take(createdAt: Self.makeUTC(year: 2026, month: 5, day: 16),
                      modifiedAt: Self.makeUTC(year: 2026, month: 5, day: 16),
                      blocks: [.textLine("third")], isNote: true)
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
                      blocks: [.textLine("first")], isNote: true)
        let t2 = Take(createdAt: Self.makeUTC(year: 2026, month: 5, day: 15),
                      modifiedAt: Self.makeUTC(year: 2026, month: 5, day: 15),
                      blocks: [.textLine("second")], isNote: true)
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
                 blocks: [.textLine("t\(i)")], isNote: true)
        }
        let out = TakeExporter.export(takes, exportedAt: exportedAt)
        XCTAssertTrue(out.contains("takes: 3\n"))
    }

    // MARK: - Special characters

    func testExport_bodyWithQuotesAndBackticks_passedThroughVerbatim() {
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 14)
        let take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        blocks: [.textLine(#"She said "go" and we ran. `code` and 'quotes'"#)],
                        isNote: true)
        let out = TakeExporter.export([take], exportedAt: exportedAt)
        XCTAssertTrue(out.contains(#"She said "go" and we ran. `code` and 'quotes'"#))
    }

    func testExport_bodyWithNewlines_preservesMultiLineBody() {
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 14)
        let take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        blocks: [.textLine("line one\nline two\nline three")],
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
                        blocks: [.textLine("# user heading\n* item")],
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
        // Specification ambiguity: a Take may have both a check item and a
        // reminder. Decision: most specific qualifier wins for the H2 — Reminder.
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 14)
        let scheduledAt = Self.makeUTC(year: 2026, month: 5, day: 20, hour: 9, minute: 0)
        var take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        blocks: [.checkItem("x", isComplete: true)], isNote: true)
        take.timeReminder = TimeReminder(scheduledDate: scheduledAt,
                                         notificationIdentifier: take.id.uuidString)
        XCTAssertEqual(TakeExporter.heading(for: take, timeZone: TimeZone(secondsFromGMT: 0)!),
                       "Reminder — 2026-05-14 · 🔔 2026-05-20 09:00")
    }

    /// Owner decision 2026-07-01: Take-level stamps render in LOCAL time. A
    /// 09:00-UTC reminder exported in UTC+3 must read 12:00 — the previous
    /// all-UTC rendering made exports read as simply wrong to the user. The
    /// `exported:` header stays ISO-UTC (file metadata, not a Take timestamp).
    func testExport_takeStamps_followInjectedZone_headerStaysUTC() {
        let createdAt = Self.makeUTC(year: 2026, month: 5, day: 16)
        let scheduledAt = Self.makeUTC(year: 2026, month: 5, day: 20, hour: 9, minute: 0)
        var take = Take(createdAt: createdAt, modifiedAt: createdAt,
                        blocks: [.textLine("Pick up prints")], isNote: true)
        take.timeReminder = TimeReminder(scheduledDate: scheduledAt,
                                         notificationIdentifier: take.id.uuidString)
        let out = TakeExporter.export([take], exportedAt: exportedAt,
                                      timeZone: TimeZone(secondsFromGMT: 3 * 3600)!)
        XCTAssertTrue(out.contains("🔔 2026-05-20 12:00"),
                      "the bell stamp must follow the injected zone — got: \(out)")
        XCTAssertTrue(out.contains("exported: 2026-06-09T"),
                      "the header keeps its UTC ISO date")
    }

    // MARK: - Filename

    func testSuggestedFilename_isCatchlightDateMd() {
        XCTAssertEqual(TakeExporter.suggestedFilename(exportedAt: exportedAt),
                       "catchlight-2026-06-09.md")
    }

    /// `isExportFilename` gates the stale-tmp-file sweep — it must match every
    /// name `suggestedFilename` can produce and nothing else.
    func testIsExportFilename_matchesExportsOnly() {
        XCTAssertTrue(TakeExporter.isExportFilename(
            TakeExporter.suggestedFilename(exportedAt: exportedAt)))
        XCTAssertTrue(TakeExporter.isExportFilename("catchlight-2026-01-01.md"))
        // A plain-text export from an earlier build must STILL sweep, or its decrypted
        // corpus lingers in tmp (owner 2026-06-21) — the matcher keeps covering `.txt`.
        XCTAssertTrue(TakeExporter.isExportFilename("catchlight-2026-01-01.txt"))

        XCTAssertFalse(TakeExporter.isExportFilename("notes-2026-01-01.md"))
        XCTAssertFalse(TakeExporter.isExportFilename("catchlight.db"))
        XCTAssertFalse(TakeExporter.isExportFilename("catchlight-2026-01-01.pdf"))
        XCTAssertFalse(TakeExporter.isExportFilename(""))

        // The diagnostics export must also be sweep-collectable (2026-07-02): its
        // tmp file was renamed capital-`C` → lowercase `catchlight-diagnostics.txt`
        // precisely so this matcher collects a crash-stranded copy. Guards the
        // naming contract between ExportCoordinator and the sweep.
        XCTAssertTrue(TakeExporter.isExportFilename("catchlight-diagnostics.txt"))
        XCTAssertFalse(TakeExporter.isExportFilename("Catchlight-diagnostics.txt"),
                       "the old capital-C name escaped the sweep — must not come back")
    }

}
