//
//  RemindersBannerDismissUITests.swift
//  CatchlightUITests
//
//  The "Enable Notifications" banner on Dailies can be dismissed, and once dismissed it stays
//  gone after the app is relaunched (owner 2026-11-12: "It needs a dismiss").
//

import XCTest

final class RemindersBannerDismissUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(keepDismissal: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-notifications-off"]
            + (keepDismissal ? ["--uitesting-keep-dismissals"] : [])
        app.launch()
        return app
    }

    func testDismissedBannerStaysHiddenAfterARelaunch() {
        var app = launch(keepDismissal: false)
        let turnOn = anyElement(in: app, id: "reminders-silenced-turn-on")
        XCTAssertTrue(turnOn.waitForExistence(timeout: 12), "the banner did not show")
        let dismiss = anyElement(in: app, id: "reminders-silenced-dismiss")
        XCTAssertTrue(dismiss.exists, "the banner has no dismiss control")
        dismiss.tap()
        XCTAssertTrue(turnOn.waitForNonExistence(timeout: 3), "the banner stayed after dismiss")
        app.terminate()

        app = launch(keepDismissal: true)
        XCTAssertTrue(anyElement(in: app, id: "add-button").waitForExistence(timeout: 12))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(anyElement(in: app, id: "reminders-silenced-turn-on").exists,
                       "the banner came back after a relaunch")
    }
}
