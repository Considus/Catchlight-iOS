//
//  LapsedReadOnlyUITests.swift
//  CatchlightUITests
//
//  After a subscription ends, Takes stay readable and Export still works, but nothing can be
//  changed until the person subscribes again (the site: "You can't add or edit until you
//  subscribe again"). Adding while lapsed is covered by PaywallUITests.
//

import XCTest

final class LapsedReadOnlyUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launchLapsed() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-lapsed"]
        app.launch()
        let dismiss = anyElement(in: app, id: "paywall-dismiss")
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5), "the subscribe screen did not open on a lapsed launch")
        dismiss.tap()
        return app
    }

    func testTakesStayReadable() {
        let app = launchLapsed()
        XCTAssertTrue(takeRow(in: app, withLabelStarting: "Call the framer back").waitForExistence(timeout: 5))
        XCTAssertTrue(takeRow(in: app, withLabelStarting: "Buy film for the weekend shoot").exists)
    }

    func testTappingATakeOpensTheSubscribeScreenNotTheEditor() {
        let app = launchLapsed()
        let row = takeRow(in: app, withLabelStarting: "Call the framer back")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(anyElement(in: app, id: "paywall-sheet").waitForExistence(timeout: 3),
                      "a lapsed tap on a Take should open the subscribe screen")
        XCTAssertFalse(app.textViews["take-edit-body"].exists, "the editor opened while lapsed")
    }

    func testExportStaysAvailable() {
        let app = launchLapsed()
        swipeUpWhenReady(anyElement(in: app, id: "angle-tab"))
        XCTAssertTrue(anyElement(in: app, id: "settings-sheet").waitForExistence(timeout: 5), "Settings did not open")
        let export = anyElement(in: app, id: "settings-export-takes")
        scrollUntilHittable(export, in: app)
        export.tap()
        let share = app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), "Export did not open the share sheet")
        XCTAssertFalse(anyElement(in: app, id: "paywall-sheet").exists, "Export was blocked by the subscribe screen")
    }
}
