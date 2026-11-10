//
//  FlatToggleUITests.swift
//  CatchlightUITests
//
//  The flat toggle and the flat segmented control on the reminder sheet behave as the native
//  ones did. Before the redesign, measured on main: each toggle was a switch with its label,
//  its identifier and the value 0 or 1, and only the switch flipped it. The Time and Place
//  choice was a segmented picker whose segments were buttons.
//

import XCTest

final class FlatToggleUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    private func openReminderSheet() -> XCUIApplication {
        let app = launchAppForUITesting()
        tapUntil(app.buttons["add-button"], appears: app.textViews["take-edit-body"])
        tapWhenReady(app.buttons["reminder-button"])
        XCTAssertTrue(anyElement(in: app, id: "reminder-allday-toggle").waitForExistence(timeout: 5))
        return app
    }

    private func value(_ element: XCUIElement) -> String { "\(element.value ?? "")" }

    /// A point on the track (the trailing 22pt of the row) or on the label (its leading 15%).
    private func onTrack(_ e: XCUIElement) -> XCUICoordinate {
        e.coordinate(withNormalizedOffset: CGVector(dx: 1 - 22 / e.frame.width, dy: 0.5))
    }
    private func onLabel(_ e: XCUIElement) -> XCUICoordinate {
        e.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
    }

    func testToggles_areSwitches_withTheNativeLabelIdentifierAndValue() {
        let app = openReminderSheet()
        let expected: [(id: String, label: String, value: String)] = [
            ("reminder-allday-toggle", "All-day", "0"),
            ("reminder-alarm-toggle", "Notify", "1"),
            ("reminder-repeat-toggle", "Repeat", "0"),
        ]
        for toggle in expected {
            let element = anyElement(in: app, id: toggle.id)
            XCTAssertEqual(element.elementType, .switch, "\(toggle.id) type")
            XCTAssertEqual(element.label, toggle.label, "\(toggle.id) label")
            XCTAssertEqual(element.identifier, toggle.id)
            XCTAssertEqual(value(element), toggle.value, "\(toggle.id) value")
            XCTAssertGreaterThanOrEqual(element.frame.height, 44, "\(toggle.id) row height")
        }
    }

    func testOnlyTheTrackFlipsIt_byTapOrByDrag() {
        let app = openReminderSheet()
        let toggle = anyElement(in: app, id: "reminder-allday-toggle")
        XCTAssertEqual(value(toggle), "0")

        onLabel(toggle).tap()
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(value(toggle), "0", "tapping the label must not flip it")

        onTrack(toggle).tap()
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(value(toggle), "1", "tapping the track flips it on")

        // The sheet moves when All-day is on, so find the row again.
        let moved = anyElement(in: app, id: "reminder-allday-toggle")
        let track = onTrack(moved)
        track.withOffset(CGVector(dx: 6, dy: 0)).press(forDuration: 0.05,
                                                      thenDragTo: track.withOffset(CGVector(dx: -16, dy: 0)))
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(value(moved), "0", "dragging the track to the leading side sets it off")

        let again = onTrack(anyElement(in: app, id: "reminder-allday-toggle"))
        again.withOffset(CGVector(dx: -8, dy: 0)).press(forDuration: 0.05,
                                                       thenDragTo: again.withOffset(CGVector(dx: 14, dy: 0)))
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(value(anyElement(in: app, id: "reminder-allday-toggle")), "1",
                       "dragging the track to the trailing side sets it on")
    }
}
