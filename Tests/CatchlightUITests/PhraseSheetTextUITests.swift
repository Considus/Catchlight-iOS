//
//  PhraseSheetTextUITests.swift
//  CatchlightUITests
//
//  At the largest text size the line under "Reveal your Privacy phrase" wraps in full,
//  and the sheet scrolls when it must, rather than cutting the sentence short.
//

import XCTest

final class PhraseSheetTextUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testExplanationWrapsInFullAtTheLargestSize() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-phrase",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let body = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Authenticate with Face ID'")).firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 12), "the explanation did not appear")
        Thread.sleep(forTimeInterval: 1)
        // Before the fix the sentence was cut to three lines, 152.5pt tall on the iPhone SE,
        // ending "your device pas…". In full it needs more than twice that.
        XCTAssertGreaterThan(body.frame.height, 2 * 152.5, "the explanation is cut short")
        // Its last line can be scrolled clear of the Reveal phrase button.
        let pill = app.buttons["Reveal phrase"]
        for _ in 0..<4 where body.frame.maxY > pill.frame.minY { app.swipeUp(velocity: .slow) }
        XCTAssertLessThanOrEqual(body.frame.maxY, pill.frame.minY, "the explanation ends under the button")
        XCTAssertTrue(pill.isHittable)
    }
}
