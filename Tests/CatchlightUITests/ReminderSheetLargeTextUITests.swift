//
//  ReminderSheetLargeTextUITests.swift
//  CatchlightUITests
//
//  At the largest text size the reminder sheet never breaks a word inside itself: a row whose
//  title and control don't fit on one line stacks them, and the Arrive / Leave choice stacks
//  its two options rather than cutting them short.
//

import XCTest

final class ReminderSheetLargeTextUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL"] + extra
        app.launch()
        return app
    }

    /// One line of a title, as tall as the Radius title, which always has a line to itself.
    private func assertOneLine(_ element: XCUIElement, _ line: CGFloat, _ name: String,
                               file: StaticString = #filePath, lineNo: UInt = #line) {
        XCTAssertTrue(element.exists, "\(name) not found", file: file, line: lineNo)
        XCTAssertLessThanOrEqual(element.frame.height, line + 1, "\(name) broke over more than one line",
                                 file: file, line: lineNo)
    }

    func testNoWordBreaksInsideItself_onEitherTab() {
        let app = launch(["--uitesting-place-reminder"])
        tapWhenReady(takeRow(in: app, withLabelStarting: "Buy film for the weekend shoot"))
        tapWhenReady(anyElement(in: app, id: "reminder-button"))
        let radius = app.staticTexts["Radius"]
        XCTAssertTrue(radius.waitForExistence(timeout: 8))
        sleep(1)
        let line = radius.frame.height

        // Place tab. Before the fix: "Not / ify", "Pla / ce", and "When I ar…" beside "When I le…".
        assertOneLine(app.staticTexts["Notify"], line, "Notify")
        assertOneLine(app.staticTexts["Place"], line, "Place")
        let arrive = app.buttons["When I arrive"], leave = app.buttons["When I leave"]
        XCTAssertTrue(arrive.exists && leave.exists)
        XCTAssertLessThanOrEqual(arrive.frame.maxY, leave.frame.minY + 1,
                                 "Arrive and Leave sit side by side, cut short, where they don't fit")

        // Time tab. Before the fix: "Ti / me" beside the time, and the Quick set value cut to "Sel…".
        tapWhenReady(app.buttons["Time"])
        let quick = app.staticTexts["Quick set"], select = app.staticTexts["Select"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        sleep(1)
        assertOneLine(app.staticTexts["Time"], line, "Time")
        XCTAssertGreaterThanOrEqual(select.frame.minY, quick.frame.maxY - 1,
                                    "the Quick set value sits beside its title, cut short, where they don't fit")
    }
}
