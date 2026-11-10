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

    func testTimePlaceSegments_areButtonsOfAtLeast44_withTheSelectedTrait() {
        let app = openReminderSheet()
        let time = app.buttons["Time"], place = app.buttons["Place"]
        XCTAssertTrue(time.exists && place.exists, "segments are buttons labelled Time and Place")
        XCTAssertGreaterThanOrEqual(time.frame.height, 44, "Time segment height \(time.frame.height)")
        XCTAssertGreaterThanOrEqual(place.frame.height, 44, "Place segment height \(place.frame.height)")
        XCTAssertGreaterThanOrEqual(time.frame.width, 44)
        XCTAssertTrue(time.isSelected, "Time starts selected")
        XCTAssertFalse(place.isSelected)
        XCTAssertTrue(anyElement(in: app, id: "reminder-mode").exists, "the group keeps its identifier")

        place.tap()
        XCTAssertTrue(app.buttons["Place"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Place"].isSelected, "tapping Place selects it")
        XCTAssertFalse(app.buttons["Time"].isSelected)
        XCTAssertTrue(anyElement(in: app, id: "location-use-current").waitForExistence(timeout: 3),
                      "the place controls replace the time controls")
        // The arrive and leave choice appears only once a place is chosen, so it is not
        // reachable here. It is the same `FlatSegmentedControl`.
    }

    // MARK: - The track's drag does not take scrolling or sheet dismissal

    /// A vertical drag of `dy` points starting `dx` from the element's leading edge.
    private func drag(from element: XCUIElement, dxFromTrailing: CGFloat, dy: CGFloat) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 1 - dxFromTrailing / element.frame.width, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)))
    }

    private func settingsRowMovedBySwipe(fromTrack: Bool) -> (moved: CGFloat, value: String, before: String) {
        let app = launchAppForUITesting()
        swipeUpWhenReady(anyElement(in: app, id: "angle-tab"))
        XCTAssertTrue(anyElement(in: app, id: "settings-sheet").waitForExistence(timeout: 5))
        let toggle = anyElement(in: app, id: "follow-up-reminders-toggle")
        var scrolls = 0
        while !(toggle.exists && toggle.isHittable) && scrolls < 10 {
            let list = anyElement(in: app, id: "settings-sheet")
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)))
            Thread.sleep(forTimeInterval: 0.5)
            scrolls += 1
        }
        XCTAssertTrue(toggle.exists && toggle.isHittable, "the Follow-up reminders row is not reachable after \(scrolls) scrolls")
        let before = value(toggle)
        let yBefore = toggle.frame.minY
        drag(from: toggle, dxFromTrailing: fromTrack ? 22 : toggle.frame.width * 0.7, dy: -220)
        Thread.sleep(forTimeInterval: 0.8)
        let after = anyElement(in: app, id: "follow-up-reminders-toggle")
        let result = (yBefore - after.frame.minY, value(after), before)
        app.terminate()
        return result
    }

    func testSettings_verticalSwipeStartingOnAToggleTrack_scrollsTheList_andLeavesTheToggle() {
        let fromLabel = settingsRowMovedBySwipe(fromTrack: false)
        let fromTrack = settingsRowMovedBySwipe(fromTrack: true)
        XCTAssertGreaterThan(fromLabel.moved, 50, "control: a swipe from the label must scroll the list (\(fromLabel.moved))")
        XCTAssertEqual(fromTrack.value, fromTrack.before, "a vertical swipe on the track must not change the toggle")
        XCTAssertEqual(fromTrack.moved, fromLabel.moved, accuracy: 25,
                       "the list scrolled \(fromTrack.moved) from the track and \(fromLabel.moved) from the label")
    }

    /// Opens the reminder sheet, swipes down from the label or from the track of the All-day
    /// row, and reports whether the sheet is still up and the toggle's value.
    private func swipeDownOnReminderSheet(fromTrack: Bool) -> (sheetUp: Bool, value: String, moved: CGFloat) {
        let app = openReminderSheet()
        let toggle = anyElement(in: app, id: "reminder-allday-toggle")
        let yBefore = toggle.frame.minY
        let startX: CGFloat = fromTrack ? 22 : toggle.frame.width * 0.85   // from the trailing edge
        drag(from: toggle, dxFromTrailing: startX, dy: 320)
        Thread.sleep(forTimeInterval: 1.2)
        let after = anyElement(in: app, id: "reminder-allday-toggle")
        let up = after.exists
        let result = (up, up ? value(after) : "", up ? after.frame.minY - yBefore : .nan)
        app.terminate()
        return result
    }

    func testReminderSheet_downwardSwipeStartingOnATrack_behavesLikeOneStartingOnTheLabel() {
        let fromLabel = swipeDownOnReminderSheet(fromTrack: false)
        let fromTrack = swipeDownOnReminderSheet(fromTrack: true)
        XCTAssertEqual(fromTrack.sheetUp, fromLabel.sheetUp,
                       "sheet still up after a swipe from the track: \(fromTrack.sheetUp), from the label: \(fromLabel.sheetUp)")
        if fromTrack.sheetUp {
            XCTAssertEqual(fromTrack.moved, fromLabel.moved, accuracy: 4, "the sheet scrolled differently from the track")
            XCTAssertEqual(fromTrack.value, "0", "the toggle must be unchanged")
        }
        XCTAssertEqual(fromLabel.sheetUp, fromTrack.sheetUp)
    }
}
