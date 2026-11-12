//
//  ReadOnlyLookUITests.swift
//  CatchlightUITests
//
//  The read-only strip after a subscription ends says "Read-only. Your Takes are still
//  yours." (owner 2026-11-12, replacing "Your data"), whole and unclipped beside Export
//  and Subscribe. Add looks locked while read-only (owner 2026-11-12, "Looks locked"): same
//  place and tap area, still opens the subscribe screen, read by VoiceOver as locked.
//

import XCTest

final class ReadOnlyLookUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testStripSaysYourTakesAreStillYours() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-lapsed"]
        app.launch()
        let dismiss = anyElement(in: app, id: "paywall-dismiss")
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        dismiss.tap()
        let line = app.staticTexts["Read-only. Your Takes are still yours."]
        XCTAssertTrue(line.waitForExistence(timeout: 3), "the strip doesn't say the approved line")
        let export = anyElement(in: app, id: "lapse-banner-export")
        XCTAssertLessThanOrEqual(line.frame.maxX, export.frame.minX, "the line runs under Export")
    }

    func testAddReadsAsLockedWhileReadOnly_andStillOpensTheSubscribeScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-lapsed"]
        app.launch()
        let dismiss = anyElement(in: app, id: "paywall-dismiss")
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        dismiss.tap()
        let add = app.buttons["add-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertEqual(add.label, "Add Take, locked")
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        add.tap()
        XCTAssertTrue(anyElement(in: app, id: "paywall-sheet").waitForExistence(timeout: 3),
                      "a locked Add should still open the subscribe screen")
    }

    func testAddReadsAsAddTakeWhenSubscribed() {
        let app = launchAppForUITesting()
        let add = app.buttons["add-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        XCTAssertEqual(add.label, "Add Take")
    }
}
