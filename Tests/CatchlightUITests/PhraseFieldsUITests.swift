//
//  PhraseFieldsUITests.swift
//  CatchlightUITests
//
//  Accessibility audit 2026-08, findings V8 and T7 (the recovery-phrase
//  grid) — each of the twelve fields must say which word it is. Reached via
//  the `--uitesting-restore` seam (Wiring + SettingsView), because the grid's
//  two hosts are otherwise unreachable under test.
//
//  The 44pt touch-target half (T7) and the spoken experience are the owner's
//  device pass; labels are the machine-assertable half.
//

import XCTest

final class PhraseFieldsUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// V8: the fields must carry positional labels — the audit measured twelve
    /// identical, unlabelled text boxes.
    func testPhraseFields_carryPositionalLabels() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-restore"]
        app.launch()

        let word3 = anyElement(in: app, id: "restore-word-3")
        XCTAssertTrue(word3.waitForExistence(timeout: 8),
                      "restore-word-3 did not appear — did the --uitesting-restore seam land on the grid?")
        XCTAssertEqual(word3.label, "Word 3 of 12",
                       "Each phrase field must say which word it is (V8)")

        let word12 = anyElement(in: app, id: "restore-word-12")
        XCTAssertTrue(word12.waitForExistence(timeout: 3))
        XCTAssertEqual(word12.label, "Word 12 of 12")
    }
}
