//
//  FocusRowMotionUITests.swift
//  CatchlightUITests
//
//  How the Focus row takes taps while it opens. UI tests normally skip the row's motion;
//  here `-catchlight.focusRowFreezeAt` holds the second open at one instant of its motion,
//  so a tap lands on a known layout with no timing.
//

import XCTest

final class FocusRowMotionUITests: XCTestCase {

    /// Seconds into the open the row is held at (150ms: the marks are past half their 220ms
    /// drop, still stacked, since none slides until the drop ends).
    private let freezeAt = 0.15

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func tap(_ app: XCUIApplication, at point: CGPoint) {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x, dy: point.y)).tap()
    }

    /// Before the redesign Note was drawn on top of the gathered marks, so a tap on the stack,
    /// once the marks are past half their drop and before they slide apart, toggles Note. With
    /// the old order it toggled Task, the next mark down.
    ///
    /// The first open plays instantly, to make the Take a Task. The second is held at 150ms by
    /// the freeze hook, so the tap is judged against the layout at that instant however slowly
    /// the runner delivers it.
    func testTapOnTheGatheredMarks_togglesNote() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-catchlight.focusRowFreezeAt", String(freezeAt)]
        app.launch()
        let iris = anyElement(in: app, id: "take-iris")
        XCTAssertTrue(iris.waitForExistence(timeout: 10), "No Take on the timeline")
        let hub = CGPoint(x: iris.frame.midX, y: iris.frame.midY)
        let note = anyElement(in: app, id: "focus-row-mark-note")
        let task = anyElement(in: app, id: "focus-row-mark-task")
        let remind = anyElement(in: app, id: "focus-row-mark-remind")
        let important = anyElement(in: app, id: "focus-row-mark-important")
        let dim = anyElement(in: app, id: "focus-row-dim")

        // Make the Take a Task too, so the Note mark can turn off: on a plain Note it is the
        // floor and a tap leaves it on.
        tapPointWhenHittable(app, at: hub, after: iris)
        XCTAssertTrue(waitUntilHittable(task), "Focus row did not open")
        task.tap()
        XCTAssertEqual(task.value as? String, "active", "Task did not turn on")
        dim.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(task.waitForNonExistence(timeout: slowRunnerTimeout), "The row did not close")

        // Open again, held at 150ms. The layout is frozen, so read where Note and Task overlap
        // (no mark has started to slide) and tap the centre of that overlap, the deepest point of
        // the stack, whatever the screen width.
        // Existence, not hittable: held at 150ms the marks are stacked, so a mark's centre can be
        // another mark's, and `isHittable` would say no for a row that is open.
        tapPointWhenHittable(app, at: hub, after: iris)
        XCTAssertTrue(note.waitForExistence(timeout: slowRunnerTimeout), "Focus row did not open again")
        XCTAssertEqual(note.value as? String, "active", "Note should start on")
        let overlap = note.frame.intersection(task.frame)
        let point = CGPoint(x: overlap.midX, y: overlap.midY)
        XCTAssertGreaterThanOrEqual(point.x - note.frame.minX, 8, "Tap point too near Note's left edge")
        XCTAssertGreaterThanOrEqual(note.frame.maxX - point.x, 8, "Tap point too near Note's right edge")
        XCTAssertGreaterThanOrEqual(point.y - note.frame.minY, 8, "Tap point too near Note's top edge")
        XCTAssertGreaterThanOrEqual(note.frame.maxY - point.y, 8, "Tap point too near Note's bottom edge")
        XCTAssertTrue(point.y > hub.y + 22, "Tap point is on the Iris, not the marks")
        tap(app, at: point)
        XCTAssertTrue(dim.exists, "The row closed: the tap did not reach a mark")
        XCTAssertEqual(task.value as? String, "active", "The tap toggled Task, not Note")
        XCTAssertEqual(important.value as? String, "inactive", "The tap toggled Important, not Note")
        XCTAssertEqual(remind.value as? String, "inactive", "The tap toggled Reminder, not Note")
        XCTAssertEqual(note.value as? String, "inactive", "The tap did not toggle Note")
    }
}
