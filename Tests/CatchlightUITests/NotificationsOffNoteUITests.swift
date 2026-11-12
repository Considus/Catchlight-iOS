//
//  NotificationsOffNoteUITests.swift
//  CatchlightUITests
//
//  With iOS notifications off, a reminder whose Notify is on can't alert. The time and place
//  editors say so under Notify, beside the timeline strip's own "Turn on" (owner 2026-11-12:
//  "Whatever that is, just do that next to it").
//

import XCTest

final class NotificationsOffNoteUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func openReminderSheet(notificationsOff: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"] + (notificationsOff ? ["--uitesting-notifications-off"] : [])
        app.launch()
        tapUntil(app.buttons["add-button"], appears: app.textViews["take-edit-body"])
        tapWhenReady(app.buttons["reminder-button"])
        XCTAssertTrue(anyElement(in: app, id: "reminder-alarm-toggle").waitForExistence(timeout: 5))
        return app
    }

    private func assertNoteLayout(_ app: XCUIApplication, _ editor: String) {
        let turnOn = app.buttons["notifications-off-turn-on"]
        XCTAssertTrue(turnOn.waitForExistence(timeout: 3), "\(editor): no Turn on beside the note")
        XCTAssertEqual(turnOn.label, "Turn on notifications", "\(editor): VoiceOver label")
        XCTAssertGreaterThanOrEqual(turnOn.frame.height, 44, "\(editor): Turn on hit height")
        let note = app.staticTexts["Notifications are off, so this won't notify you."]
        XCTAssertTrue(note.exists, "\(editor): the note's words")
        XCTAssertGreaterThanOrEqual(turnOn.frame.minX - note.frame.maxX, 8, "\(editor): gap between note and Turn on")
        XCTAssertEqual(turnOn.frame.minY, note.frame.minY, accuracy: 1, "\(editor): Turn on top-aligned with the note")
    }

    func testTimeEditor_saysNotifyCantAlert_onlyWhileNotifyIsOn() {
        let app = openReminderSheet(notificationsOff: true)
        assertNoteLayout(app, "time editor")

        let toggle = app.switches["reminder-alarm-toggle"]
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 1 - 22 / toggle.frame.width, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["notifications-off-turn-on"].waitForNonExistence(timeout: 3),
                      "time editor: the note stayed with Notify off")
    }

    func testPlaceEditor_saysNotifyCantAlert_onlyWhileNotifyIsOn() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-notifications-off", "--uitesting-place-reminder"]
        app.launch()
        tapWhenReady(takeRow(in: app, withLabelStarting: "Buy film for the weekend shoot"))
        tapWhenReady(anyElement(in: app, id: "reminder-button"))
        let toggle = app.switches["location-notify-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the place editor's Notify row did not show")
        assertNoteLayout(app, "place editor")

        toggle.coordinate(withNormalizedOffset: CGVector(dx: 1 - 22 / toggle.frame.width, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["notifications-off-turn-on"].waitForNonExistence(timeout: 3),
                      "place editor: the note stayed with Notify off")
    }

    func testNoNote_whileNotificationsAreAllowedOrNotYetAsked() {
        let app = openReminderSheet(notificationsOff: false)
        XCTAssertFalse(app.buttons["notifications-off-turn-on"].waitForExistence(timeout: 2))
    }
}
