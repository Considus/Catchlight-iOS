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
}
