//
//  MenuFieldRowUITests.swift
//  CatchlightUITests
//
//  A menu row whose title and value don't fit on one line stacks them, so the value
//  is never broken mid-word.
//

import XCTest

final class MenuFieldRowUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSyncValueStaysOnOneLineAtTheLargestSize() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-cloud-storage", "--uitesting-cloud-folder",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sync'")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 12))
        Thread.sleep(forTimeInterval: 1)
        let title = menu.staticTexts["Sync"]
        // Whichever mode is set (Disabled, Manual or Automatic): the value is the row's other text.
        let value = menu.staticTexts.matching(NSPredicate(format: "label != 'Sync'")).firstMatch
        XCTAssertTrue(title.exists && value.exists)
        // One line of the value is no taller than one line of the title, in the same font.
        // Before the fix the value broke as "Man-ual" over two lines.
        XCTAssertLessThanOrEqual(value.frame.height, title.frame.height + 0.5, "the value wrapped")
    }
}
