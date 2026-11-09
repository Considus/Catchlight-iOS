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
}
