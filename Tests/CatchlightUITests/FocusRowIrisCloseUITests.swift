//
//  FocusRowIrisCloseUITests.swift
//  CatchlightUITests
//
//  With the Focus row open, a tap on the Iris saves the row's choice and closes it, every
//  time, as a tap on any dimmed area does. Before the redesign the Iris's hollow centre let
//  the tap through to the dimmed area; the redesigned Iris is drawn solid, and it swallowed
//  the tap (owner: "1 to 8 attempts").
//

import XCTest

final class FocusRowIrisCloseUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Opens the row from the top Take's Iris, turns Task on, taps the Iris once at `offset`
    /// from its top-left corner, and checks the row closed with Task saved.
    private func assertIrisTapClosesAndSaves(at offset: (CGRect) -> CGPoint, _ name: String,
                                             file: StaticString = #filePath, line: UInt = #line) {
        let app = launchAppForUITesting()
        let iris = anyElement(in: app, id: "take-iris")
        XCTAssertTrue(iris.waitForExistence(timeout: 10), "No Take on the timeline", file: file, line: line)
        let frame = iris.frame
        iris.tap()
        let dim = anyElement(in: app, id: "focus-row-dim")
        let task = anyElement(in: app, id: "focus-row-mark-task")
        XCTAssertTrue(dim.waitForExistence(timeout: 5), "Focus row did not open", file: file, line: line)
        sleep(1) // fully open (UI tests skip the motion; this is margin)
        // The Iris copy in the row still reads its selection to VoiceOver.
        XCTAssertTrue(app.descendants(matching: .any)
                        .matching(NSPredicate(format: "label BEGINSWITH 'Selected:'")).firstMatch.exists,
                      "The row's Iris lost its VoiceOver element", file: file, line: line)
        task.tap()
        XCTAssertEqual(task.value as? String, "active", "Task did not turn on", file: file, line: line)

        let point = offset(frame)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
        XCTAssertTrue(dim.waitForNonExistence(timeout: 3),
                      "\(name): a tap on the Iris at \(point) did not close the row", file: file, line: line)

        // Saved: open the row again and Task is on.
        sleep(1)
        anyElement(in: app, id: "take-iris").tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5), "Focus row did not reopen", file: file, line: line)
        XCTAssertEqual(task.value as? String, "active", "\(name): the row closed without saving Task",
                       file: file, line: line)
    }

    func testIrisTap_centre_closesAndSaves() {
        assertIrisTapClosesAndSaves(at: { CGPoint(x: $0.midX, y: $0.midY) }, "centre")
    }

    func testIrisTap_nearTopLeft_closesAndSaves() {
        assertIrisTapClosesAndSaves(at: { CGPoint(x: $0.minX + 6, y: $0.minY + 6) }, "top left")
    }

    func testIrisTap_nearTopRight_closesAndSaves() {
        assertIrisTapClosesAndSaves(at: { CGPoint(x: $0.maxX - 6, y: $0.minY + 6) }, "top right")
    }

    func testIrisTap_nearBottomRight_closesAndSaves() {
        assertIrisTapClosesAndSaves(at: { CGPoint(x: $0.maxX - 6, y: $0.maxY - 6) }, "bottom right")
    }
}
