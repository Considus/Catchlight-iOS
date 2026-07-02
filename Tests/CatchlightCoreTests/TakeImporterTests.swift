//
//  TakeImporterTests.swift
//  CatchlightCoreTests — import notes as Takes (owner 2026-06-22)
//
//  One file = one Take; checklist lines become check items (so the Take derives
//  as a Task); plain prose stays a Note. Empty files are skipped.
//

import XCTest
@testable import CatchlightCore

final class TakeImporterTests: XCTestCase {

    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Plain prose

    func testPlainProse_isOneNoteTake() throws {
        let take = try XCTUnwrap(TakeImporter.parse("Buy film for the weekend shoot", fileDate: date))
        XCTAssertEqual(take.plainText, "Buy film for the weekend shoot")
        XCTAssertEqual(take.isTask, false)
        XCTAssertEqual(take.isNote, true)
        XCTAssertEqual(take.createdAt.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 1)
    }

    func testMultiLineProse_collapsesIntoOneTextBlock() {
        let take = TakeImporter.parse("line one\nline two\nline three", fileDate: date)
        XCTAssertEqual(take?.blocks.count, 1)
        XCTAssertEqual(take?.plainText, "line one\nline two\nline three")
    }

    // MARK: - Checklists

    func testChecklistLines_becomeCheckItems_andTaskDerives() {
        let take = TakeImporter.parse("- [ ] passport\n- [x] charger", fileDate: date)
        XCTAssertEqual(take?.isTask, true)
        XCTAssertEqual(take?.blocks.count, 2)
        XCTAssertEqual(take?.checkItems.map(\.text), ["passport", "charger"])
        XCTAssertEqual(take?.checkItems.map(\.isComplete), [false, true])
    }

    func testCheckboxVariants_allRecognised() {
        let take = TakeImporter.parse("[ ] a\n[x] b\n* [X] c\n-  [ ] d", fileDate: date)
        XCTAssertEqual(take?.checkItems.map(\.text), ["a", "b", "c", "d"])
        XCTAssertEqual(take?.checkItems.map(\.isComplete), [false, true, true, false])
    }

    func testCompletedChecklist_isComplete() {
        let take = TakeImporter.parse("- [x] only item", fileDate: date)
        XCTAssertEqual(take?.isComplete, true)
    }

    func testMixedProseAndChecklist_preservesOrder() {
        let take = TakeImporter.parse("Packing list\n- [x] passport\n- [ ] charger\nbuy at airport:\n- [ ] water",
                                      fileDate: date)
        let kinds = take?.blocks.map { $0.isCheck ? "check" : "text" }
        XCTAssertEqual(kinds, ["text", "check", "check", "text", "check"])
        XCTAssertEqual(take?.blocks.first?.text, "Packing list")
    }

    // MARK: - Not a checkbox

    func testMarkdownLink_isNotMistakenForCheckbox() {
        let take = TakeImporter.parse("[Catchlight](https://catchlight.app)", fileDate: date)
        XCTAssertEqual(take?.isTask, false)
        XCTAssertEqual(take?.plainText, "[Catchlight](https://catchlight.app)")
    }

    func testMidLineBracket_staysProse() {
        let take = TakeImporter.parse("the answer is [x] apparently", fileDate: date)
        XCTAssertEqual(take?.isTask, false)
    }

    // MARK: - Edge cases

    func testEmptyOrWhitespaceFile_returnsNil() {
        XCTAssertNil(TakeImporter.parse("", fileDate: date))
        XCTAssertNil(TakeImporter.parse("   \n\n  \t\n", fileDate: date))
    }

    func testCRLFLineEndings_normalised() {
        let take = TakeImporter.parse("a\r\n- [ ] b", fileDate: date)
        XCTAssertEqual(take?.blocks.count, 2)
        XCTAssertEqual(take?.blocks.first?.text, "a")
        XCTAssertEqual(take?.checkItems.map(\.text), ["b"])
    }

    // MARK: - Export → import round trip (D-104: split back into individual Takes)

    /// A single-Take export re-imports as exactly ONE reconstructed Take (not the whole
    /// file collapsed into one, and not the frontmatter/heading as stray prose): body
    /// and check states survive, and the exact createdAt round-trips via the data block.
    func testExportThenImport_singleTake_reconstructsCleanly() throws {
        var take = Take(createdAt: date, modifiedAt: date,
                        blocks: [
                            .textLine("Packing list"),
                            .checkItem("passport", isComplete: true),
                            .checkItem("charger", isComplete: false),
                            .textLine("buy water at the airport")
                        ],
                        isNote: true)
        take.normaliseActivityFloor()

        let exported = TakeExporter.export([take], exportedAt: date)
        let reimported = TakeImporter.parseDocument(exported, fileDate: date)

        XCTAssertEqual(reimported.count, 1)
        let r = try XCTUnwrap(reimported.first)
        XCTAssertEqual(r.plainText, "Packing list\npassport\ncharger\nbuy water at the airport",
                       "no frontmatter or heading leaked into the body")
        XCTAssertEqual(r.checkItems.map(\.text), ["passport", "charger"])
        XCTAssertEqual(r.checkItems.map(\.isComplete), [true, false])
        XCTAssertTrue(r.isTask)
        XCTAssertEqual(r.createdAt.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.01,
                       "exact createdAt round-trips via the data block")
    }

    /// A multi-Take export splits back into the SAME number of Takes, in order, with
    /// each Take's type, Obie flag, and reminder preserved losslessly.
    func testExportThenImport_multipleTakes_splitWithFidelity() throws {
        let d1 = Date(timeIntervalSince1970: 1_700_000_000)
        let d2 = d1.addingTimeInterval(60)
        let d3 = d2.addingTimeInterval(60)

        let note = Take(createdAt: d1, modifiedAt: d1, blocks: [.textLine("a plain note")], isNote: true)
        var obie = Take(createdAt: d2, modifiedAt: d2, blocks: [.textLine("the one Obie")], isObie: true)
        obie.normaliseActivityFloor()
        var reminderTake = Take(createdAt: d3, modifiedAt: d3, blocks: [.textLine("pick up prints")], isNote: true)
        reminderTake.timeReminder = TimeReminder(scheduledDate: d3.addingTimeInterval(86_400),
                                                 notificationIdentifier: reminderTake.id.uuidString)

        let exported = TakeExporter.export([note, obie, reminderTake], exportedAt: d1)
        let takes = TakeImporter.parseDocument(exported, fileDate: d1)

        XCTAssertEqual(takes.count, 3, "one Take per section")
        XCTAssertEqual(takes.map(\.plainText), ["a plain note", "the one Obie", "pick up prints"])
        XCTAssertTrue(takes[1].isObie, "Obie flag survives (not in the visible heading)")
        let reminder = try XCTUnwrap(takes[2].timeReminder, "reminder survives")
        XCTAssertEqual(reminder.scheduledDate.timeIntervalSince1970,
                       d3.addingTimeInterval(86_400).timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(takes[2].timeReminder?.notificationIdentifier, takes[2].id.uuidString,
                       "reminder re-targets the freshly-imported Take id")
    }

    /// An OLDER export with no data block still splits on its `## …` headings and
    /// recovers body, type, created date, and the reminder time from the heading alone.
    func testLegacyExportWithoutDataBlock_splitsOnHeadings() {
        let legacy = """
        ---
        exported: 2026-06-09T14:32:00Z
        takes: 2
        ---

        ## Note — 2026-05-14
        first note

        ## Reminder — 2026-05-16 · 🔔 2026-05-20 09:00
        pick up prints

        """
        let takes = TakeImporter.parseDocument(legacy, fileDate: date)
        XCTAssertEqual(takes.count, 2)
        XCTAssertEqual(takes.map(\.plainText), ["first note", "pick up prints"])
        XCTAssertNotNil(takes[1].timeReminder, "the bell time is recovered from the heading")
    }

    /// A foreign note (no Catchlight frontmatter) still imports as a single Take.
    func testForeignNote_viaParseDocument_isOneTake() {
        let takes = TakeImporter.parseDocument("just some notes\n- [ ] and a todo", fileDate: date)
        XCTAssertEqual(takes.count, 1)
        XCTAssertTrue(takes[0].isTask)
    }

    /// A REPEATING reminder — cadence and weekdays — round-trips via the data block, even
    /// though the visible heading only shows the next fire time (owner asked 2026-07-02).
    func testExportThenImport_recurringReminder_cadenceAndWeekdaysSurvive() throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        var take = Take(createdAt: created, modifiedAt: created,
                        blocks: [.textLine("water the plants")], isNote: true)
        take.timeReminder = TimeReminder(scheduledDate: created.addingTimeInterval(3600),
                                         notificationIdentifier: take.id.uuidString,
                                         recurrence: .weekly,
                                         weekdays: [2, 4, 6])   // Mon / Wed / Fri

        let exported = TakeExporter.export([take], exportedAt: created)
        let reimported = TakeImporter.parseDocument(exported, fileDate: created)

        XCTAssertEqual(reimported.count, 1)
        let r = try XCTUnwrap(reimported.first?.timeReminder, "reminder survives")
        XCTAssertEqual(r.recurrence, .weekly, "recurrence cadence round-trips")
        XCTAssertEqual(r.weekdays, [2, 4, 6], "recurring weekdays round-trip")
    }
}
