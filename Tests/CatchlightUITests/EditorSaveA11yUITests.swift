//
//  EditorSaveA11yUITests.swift
//  CatchlightUITests
//
//  Accessibility audit 2026-08, findings V2 (fix 3) and V1 (fix 4) — the
//  tap-away save catchers on the Dailies and Storyboard editors, and the
//  Storyboard row labels. Companion to LockedCaptureUITests (D-214 pattern).
//
//  Fixture note (per the fix prompt): the Storyboard lists only Takes that
//  carry a task and excludes the Obie. The --uitesting fixture seeds two plain
//  notes, so tests first shape the top row ("Call the framer back") into a
//  Task via its Iris + Focus ring — the Flow 2 idiom — without touching the
//  Obie state.
//

import XCTest

final class EditorSaveA11yUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Fixture shaping

    /// Shape the top seeded Take into a Task from the timeline (Flow 2 idiom):
    /// Iris → Task mark → dim-commit. Skip-guarded like BlockEditorUITests:
    /// the synthesized Focus-ring choreography is unreliable on some older
    /// simulator runtimes.
    private func shapeTopRowIntoTask(_ app: XCUIApplication) throws {
        let iris = anyElement(in: app, id: "take-iris")
        tapWhenReady(iris)
        let taskMark = app.buttons["focus-ring-mark-task"]
        try XCTSkipUnless(taskMark.waitForExistence(timeout: 3),
                          "Focus ring did not open under synthesized gestures on this runtime.")
        taskMark.tap()
        // Commit via the dim — a corner coordinate far from any mark (Flow 2).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.12)).tap()
        try XCTSkipUnless(taskMark.waitForNonExistence(timeout: 3),
                          "Focus-ring dim-commit not delivered on this runtime.")
    }

    /// Open the Storyboard and its editor on the (single) task row.
    private func openStoryboardEditor(_ app: XCUIApplication) throws {
        tapWhenReady(app.buttons["angle-tab"])
        let row = anyElement(in: app, id: "storyboard-row")
        XCTAssertTrue(row.waitForExistence(timeout: 3),
                      "Shaped task row did not appear on the Storyboard")
        tapUntil(row, appears: app.textViews["take-edit-body"])
    }

    // MARK: - V2: the save catchers are named accessibility elements

    /// Dailies: opening the inline editor must expose `dailies-save`.
    /// Queried type-agnostically (`anyElement`): a SwiftUI
    /// `.accessibilityElement()` wrapper surfaces as `.other` on some runtimes.
    func testDailiesSaveCatcher_isAccessibleWithLabel() {
        let app = launchAppForUITesting()
        let addButton = app.buttons["add-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Dock did not load")
        tapUntil(addButton, appears: app.textViews["take-edit-body"])

        let save = anyElement(in: app, id: "dailies-save")
        XCTAssertTrue(save.waitForExistence(timeout: 5),
                      "dailies-save did not appear — the save route is invisible to assistive technology")
        XCTAssertEqual(save.label, "Save and close",
                       "The save catcher's label is the Voice Control name — it must read correctly")
    }

    /// Storyboard: opening the editor on a task row must expose `storyboard-save`.
    func testStoryboardSaveCatcher_isAccessibleWithLabel() throws {
        let app = launchAppForUITesting()
        try shapeTopRowIntoTask(app)
        try openStoryboardEditor(app)

        let save = anyElement(in: app, id: "storyboard-save")
        XCTAssertTrue(save.waitForExistence(timeout: 5),
                      "storyboard-save did not appear — the save route is invisible to assistive technology")
        XCTAssertEqual(save.label, "Save and close",
                       "The save catcher's label is the Voice Control name — it must read correctly")
    }

    // MARK: - V1: Storyboard rows speak their Take's text

    /// The row label must contain the Take's text, not the bare status —
    /// "Call the framer back. Task…" rather than "Task, 0 of 1 complete".
    func testStoryboardRow_speaksTakeText() throws {
        let app = launchAppForUITesting()
        try shapeTopRowIntoTask(app)
        tapWhenReady(app.buttons["angle-tab"])

        let row = anyElement(in: app, id: "storyboard-row")
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "Shaped task row did not appear on the Storyboard")
        XCTAssertTrue(row.label.contains("Call the framer back"),
                      "Storyboard row label must speak the Take's text; got: \(row.label)")
    }
}
