//
//  FocusRowMotionUITests.swift
//  CatchlightUITests
//
//  How the Focus row takes taps while it opens. UI tests normally skip the row's motion;
//  here `-catchlight.focusRowTimeScale` plays it slowly instead, so a tap can land mid-open.
//

import XCTest

final class FocusRowMotionUITests: XCTestCase {

    /// The open plays this many times slower than on a device.
    private let timeScale = 60.0

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchSlowRow() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-catchlight.focusRowTimeScale", String(timeScale)]
        app.launch()
        return app
    }

    private func tap(_ app: XCUIApplication, at point: CGPoint) {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x, dy: point.y)).tap()
    }

    /// Before the redesign Note was drawn on top of the gathered marks, so a tap on the stack,
    /// once the marks are past half their drop and before Note slides out (about 230ms in,
    /// device time), toggles Note.
    func testTapOnTheGatheredMarks_togglesNote() throws {
        let app = launchSlowRow()
        let iris = anyElement(in: app, id: "take-iris")
        XCTAssertTrue(iris.waitForExistence(timeout: 10), "No Take on the timeline")
        let hub = CGPoint(x: iris.frame.midX, y: iris.frame.midY)
        let note = anyElement(in: app, id: "focus-row-mark-note")
        let task = anyElement(in: app, id: "focus-row-mark-task")
        let important = anyElement(in: app, id: "focus-row-mark-important")
        let dim = anyElement(in: app, id: "focus-row-dim")

        // Make the Take a Task too, so the Note mark can turn off: on a plain Note it is the
        // floor and a tap leaves it on.
        tap(app, at: hub)
        XCTAssertTrue(task.waitForExistence(timeout: 5), "Focus row did not open")
        sleep(UInt32(1.3 * timeScale))            // the whole open, with room
        task.tap()
        XCTAssertEqual(task.value as? String, "active", "Task did not turn on")
        dim.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(task.waitForNonExistence(timeout: 2 * timeScale), "The row did not close")
        sleep(2)

        // Open again and tap 40pt below the Iris centre, clear of the Iris's own 44pt square,
        // on the gathered marks.
        tap(app, at: hub)
        let opened = Date()
        XCTAssertTrue(note.waitForExistence(timeout: 5), "Focus row did not open again")
        let target = opened.addingTimeInterval(0.230 * timeScale)
        if target > Date() { Thread.sleep(until: target) }
        let tapAt = Date().timeIntervalSince(opened) / timeScale
        tap(app, at: CGPoint(x: hub.x, y: hub.y + 40))
        let tapDone = Date().timeIntervalSince(opened) / timeScale
        let report = String(format: "[focus-row-motion] stack tap sent %.0f-%.0fms device time; note=%@ important=%@ row open=%@",
                            tapAt * 1000, tapDone * 1000, String(describing: note.value),
                            String(describing: important.value), String(describing: dim.exists))
        print(report)
        let a = XCTAttachment(string: report)
        a.lifetime = .keepAlways
        add(a)
        XCTAssertLessThan(tapDone, 0.245, "The tap landed too late: the marks may have spread")
        XCTAssertTrue(dim.exists, "The row closed: the tap did not reach a mark")
        XCTAssertEqual(important.value as? String, "inactive", "The tap toggled Important, not Note")
        XCTAssertEqual(note.value as? String, "inactive", "The tap did not toggle Note")
    }
}
