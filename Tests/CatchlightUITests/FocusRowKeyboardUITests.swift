//
//  FocusRowKeyboardUITests.swift
//  CatchlightUITests
//
//  Tapping the Iris of the Take being edited puts the keyboard away before the Focus row
//  opens: a keyboard left up under the row fought the overlay and the Remind picker (owner
//  lockup 2026-06-18). Committing the row (a tap on its dimmed area) brings the keyboard back
//  to the block it was in, with the typed text intact. The redesign changes how the app looks,
//  not how this works (owner 2026-11-09).
//

import XCTest

final class FocusRowKeyboardUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Opens a new Take, types into it and waits for the keyboard. Returns the editor body.
    private func openEditor(_ app: XCUIApplication, typing text: String) -> XCUIElement {
        let addButton = app.buttons["add-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Dock did not load")
        let body = app.textViews["take-edit-body"]
        tapUntil(addButton, appears: body)
        typeWhenReady(body, text)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "Software keyboard did not appear")
        sleep(1) // let the card settle on the keyboard
        return body
    }

    /// Commits the open row with one tap on its dimmed area near the top of the screen,
    /// clear of the marks and the card.
    private func commitRow(_ app: XCUIApplication, closing mark: XCUIElement) {
        let dim = anyElement(in: app, id: "focus-row-dim")
        XCTAssertTrue(dim.waitForExistence(timeout: 3), "focus-row-dim not in the tree")
        dim.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(mark.waitForNonExistence(timeout: 5), "The Focus row did not close")
    }

    /// The keyboard is back and its caret is in the block it left: typing carries on the text.
    private func assertKeyboardBackInBlock(_ app: XCUIApplication, _ body: XCUIElement,
                                           continuing text: String,
                                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "The keyboard did not come back after the row committed", file: file, line: line)
        sleep(1)
        app.typeText(" now")
        assertBodyValue(body, becomes: text + " now",
                        "The caret did not return to the end of the block it was in", file: file, line: line)
    }

    /// `typeText` returns when the keystrokes are sent, not when the app has handled them, so a
    /// slow runner can still be mid-text. Wait for the body to settle on the expected value, then
    /// assert it exactly. A timeout fails with the last value seen.
    private func assertBodyValue(_ body: XCUIElement, becomes expected: String, _ message: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(5)
        var last = body.value as? String
        while last != expected && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            last = body.value as? String
        }
        XCTAssertEqual(last, expected, message + " (last value seen: \(last ?? "nil"))", file: file, line: line)
    }

    func testIrisTapInEditor_putsTheKeyboardAway_andCommitBringsItBack() throws {
        let app = launchAppForUITesting()
        let body = openEditor(app, typing: "Pack the tripod")

        tapWhenReady(anyElement(in: app, id: "editor-shape"))
        let taskMark = anyElement(in: app, id: "focus-row-mark-task")
        XCTAssertTrue(taskMark.waitForExistence(timeout: 5), "Focus row did not open")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5),
                      "The keyboard stayed up when the editor's Iris was tapped")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "focus-row-from-editor"
        shot.lifetime = .keepAlways
        add(shot)

        commitRow(app, closing: taskMark)
        XCTAssertTrue(body.exists, "The editor closed with the row")
        assertKeyboardBackInBlock(app, body, continuing: "Pack the tripod")
    }

    /// The Remind mark's picker opens with the keyboard already away, leaves it away when it
    /// closes, and the row's commit brings the keyboard back.
    func testReminderPickerFromEditor_keyboardReturnsAfterTheRowCommits() throws {
        let app = launchAppForUITesting()
        let body = openEditor(app, typing: "Pack the tripod")

        tapWhenReady(anyElement(in: app, id: "editor-shape"))
        let remind = anyElement(in: app, id: "focus-row-mark-remind")
        XCTAssertTrue(remind.waitForExistence(timeout: 5), "Focus row did not open")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5),
                      "The keyboard stayed up when the editor's Iris was tapped")
        remind.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Reminder picker did not open")
        XCTAssertEqual(app.keyboards.count, 0, "The keyboard covers the reminder picker")
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "Reminder picker did not close")
        XCTAssertTrue(remind.exists, "The Focus row closed with the picker")

        commitRow(app, closing: remind)
        assertKeyboardBackInBlock(app, body, continuing: "Pack the tripod")
    }

    /// Editing the pinned Obie: tapping its Iris puts the keyboard away too, and the commit
    /// brings it back. While any edit is open the pinned slot stands down
    /// (`DailiesView.pinnedObieStandsDown`), so the Obie's Iris on screen is the editing card's.
    func testIrisTapWhileEditingTheObie_putsTheKeyboardAway_andCommitBringsItBack() throws {
        let app = launchAppForUITesting()
        let row = takeRow(in: app, withLabelStarting: "Buy film")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Seeded Take not on the timeline")
        // The card's long-press menu, not the Iris press (synthesized leading-edge long
        // presses are not delivered on the simulator, see CoreFlows Flow 4).
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).press(forDuration: 1.2)
        let makeObie = app.buttons["Make Obie"]
        XCTAssertTrue(makeObie.waitForExistence(timeout: 5), "Long-press menu did not appear")
        makeObie.tap()
        let obieRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "take-row", "Obie"))
            .firstMatch
        XCTAssertTrue(obieRow.waitForExistence(timeout: 5), "No pinned Obie")

        let body = app.textViews["take-edit-body"]
        tapUntil(obieRow, appears: body)
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { body.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "Software keyboard did not appear")
        sleep(1)
        let text = body.value as? String ?? ""

        // The stood-down pinned slot is invisible and takes no touches, but stays in the
        // accessibility tree with the same identifier, so take the lower Iris: the editing card's.
        let irises = app.descendants(matching: .any).matching(identifier: "editor-shape")
        XCTAssertTrue(irises.firstMatch.waitForExistence(timeout: 5), "editor-shape not in the tree")
        let iris = irises.allElementsBoundByIndex.max { $0.frame.minY < $1.frame.minY }!
        iris.tap()
        let taskMark = anyElement(in: app, id: "focus-row-mark-task")
        XCTAssertTrue(taskMark.waitForExistence(timeout: 5), "Focus row did not open")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5),
                      "The keyboard stayed up when the Obie's Iris was tapped while editing")

        commitRow(app, closing: taskMark)
        // The caret returns to the block it was in; where in it depends on where the tap put it,
        // so only check the keyboard and that nothing was lost.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "The keyboard did not come back after the row committed")
        assertBodyValue(body, becomes: text, "The Obie's text changed")
    }
}
