//
//  FocusRowKeyboardUITests.swift
//  CatchlightUITests
//
//  Opening the Focus row from the editor's Iris dropped the keyboard, and the editing card,
//  anchored on the keyboard, fell to the bottom of the screen (owner, slice 1). The keyboard
//  has to stay up while the row is open, so the card stays where it was. The Remind mark's
//  picker is the one exception: it fills the screen, so the keyboard steps down while it shows
//  and comes back when it closes.
//

import XCTest

final class FocusRowKeyboardUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFocusRowFromEditor_keepsTheKeyboardUp_andTheCardInPlace() throws {
        let app = launchAppForUITesting()
        let addButton = app.buttons["add-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Dock did not load")
        let body = app.textViews["take-edit-body"]
        tapUntil(addButton, appears: body)
        typeWhenReady(body, "Pack the tripod")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "Software keyboard did not appear")
        sleep(1) // let the card settle on the keyboard

        let iris = anyElement(in: app, id: "editor-shape")
        XCTAssertTrue(iris.waitForExistence(timeout: 5), "editor-shape not in the tree")
        let before = iris.frame

        iris.tap()
        let taskMark = anyElement(in: app, id: "focus-row-mark-task")
        XCTAssertTrue(taskMark.waitForExistence(timeout: 5), "Focus row did not open")
        sleep(1) // let any keyboard dismissal and card drop finish

        let shot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: shot)
        a.name = "focus-row-from-editor"
        a.lifetime = .keepAlways
        add(a)

        let open = iris.exists ? iris.frame : .null
        let report = "[focus-row-keyboard] keyboards=\(app.keyboards.count) irisBefore=\(NSCoder.string(for: before)) irisOpen=\(NSCoder.string(for: open)) markTask=\(NSCoder.string(for: taskMark.frame)) keyboard=\(NSCoder.string(for: app.keyboards.firstMatch.frame))"
        print(report)
        let note = XCTAttachment(string: report)
        note.lifetime = .keepAlways
        add(note)

        XCTAssertGreaterThan(app.keyboards.count, 0,
                             "The keyboard dropped when the Focus row opened from the editor")
        XCTAssertFalse(open.isNull, "The editing card's Iris is not readable while the row is open")
        XCTAssertEqual(open.minY, before.minY, accuracy: 2,
                       "The editing card moved: Iris top \(before.minY) before, \(open.minY) with the row open")
    }

    func testReminderPickerFromEditor_dropsTheKeyboard_andGivesItBackOnClose() throws {
        let app = launchAppForUITesting()
        let addButton = app.buttons["add-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Dock did not load")
        let body = app.textViews["take-edit-body"]
        tapUntil(addButton, appears: body)
        typeWhenReady(body, "Pack the tripod")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "Software keyboard did not appear")
        sleep(1)

        let iris = anyElement(in: app, id: "editor-shape")
        XCTAssertTrue(iris.waitForExistence(timeout: 5), "editor-shape not in the tree")
        iris.tap()
        let remind = anyElement(in: app, id: "focus-row-mark-remind")
        XCTAssertTrue(remind.waitForExistence(timeout: 5), "Focus row did not open")
        remind.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Reminder picker did not open")
        sleep(1)
        let shot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: shot)
        a.name = "reminder-picker-from-editor"
        a.lifetime = .keepAlways
        add(a)
        XCTAssertEqual(app.keyboards.count, 0, "The keyboard covers the reminder picker")

        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "Reminder picker did not close")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "The keyboard did not come back when the picker closed")
        XCTAssertTrue(remind.exists, "The Focus row closed with the picker")
    }

    /// Editing the pinned Obie: tapping its Iris must keep the keyboard up too (the same
    /// report as any other Take). While any edit is open the pinned slot stands down
    /// (`DailiesView.pinnedObieStandsDown`), so the Obie's Iris on screen is the editing card's.
    func testFocusRowWhileEditingTheObie_keepsTheKeyboardUp() throws {
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

        // The stood-down pinned slot is invisible and takes no touches, but stays in the
        // accessibility tree with the same identifier, so take the lower Iris: the editing card's.
        let irises = app.descendants(matching: .any).matching(identifier: "editor-shape")
        XCTAssertTrue(irises.firstMatch.waitForExistence(timeout: 5), "editor-shape not in the tree")
        let all = irises.allElementsBoundByIndex
        print("[focus-row-keyboard] obie editor-shape frames: \(all.map { NSCoder.string(for: $0.frame) })")
        let iris = all.max { $0.frame.minY < $1.frame.minY }!
        let before = iris.frame
        iris.tap()
        XCTAssertTrue(anyElement(in: app, id: "focus-row-mark-task").waitForExistence(timeout: 5),
                      "Focus row did not open")
        sleep(1)
        XCTAssertGreaterThan(app.keyboards.count, 0,
                             "The keyboard dropped when the Focus row opened while editing the Obie")
        XCTAssertEqual(iris.frame.minY, before.minY, accuracy: 2, "The Obie's editing card moved")
    }

    /// While the row is open, the editor's keyboard toolbar must not act underneath it: its
    /// Discard does what a tap on the dimmed area does (save the row's choice and close it).
    func testToolbarDiscard_whileTheFocusRowIsOpen_doesNotDiscard() throws {
        let app = launchAppForUITesting()
        let addButton = app.buttons["add-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Dock did not load")
        let body = app.textViews["take-edit-body"]
        tapUntil(addButton, appears: body)
        typeWhenReady(body, "Pack the tripod")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "Software keyboard did not appear")
        sleep(1)

        anyElement(in: app, id: "editor-shape").tap()
        let taskMark = anyElement(in: app, id: "focus-row-mark-task")
        XCTAssertTrue(taskMark.waitForExistence(timeout: 5), "Focus row did not open")
        let discard = app.buttons["Discard changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "Keyboard toolbar not showing")
        discard.tap()
        sleep(1)

        XCTAssertTrue(taskMark.waitForNonExistence(timeout: 5), "The Focus row did not close")
        XCTAssertTrue(body.exists, "The editor closed: the Take was discarded under the Focus row")
        XCTAssertEqual(body.value as? String, "Pack the tripod", "The edit was lost")
    }
}
