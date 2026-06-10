//
//  PaywallUITests.swift
//  CatchlightUITests — Task 6.20
//
//  Drives the paywall sheet end-to-end through the real app UI. Uses the
//  `--uitesting-lapsed` launch argument (consumed by `Wiring.makeAppModel`)
//  to force `SubscriptionStatus.lapsed` on launch — every other UI test in
//  the suite runs with the default `.subscribed` so their flows aren't gated.
//

import XCTest

final class PaywallUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The paywall appears on the lapsed-launch entry because the post-
    /// onboarding hook fires when the app first becomes interactive.
    func testPaywall_appearsOnLapsedLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-lapsed"]
        app.launch()

        let sheet = app.descendants(matching: .any)
            .matching(identifier: "paywall-sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3),
                      "Paywall should appear automatically when the user is lapsed.")
    }

    /// Tapping the Add button while lapsed re-opens the paywall instead of
    /// creating a Take (the dismiss-then-tap path).
    func testPaywall_addTakeWhileLapsedReopensPaywall() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-lapsed"]
        app.launch()

        // Dismiss the auto-presented paywall to get to the timeline.
        let dismiss = app.descendants(matching: .any)
            .matching(identifier: "paywall-dismiss").firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 3))
        dismiss.tap()

        // Open the Add bloom, then tap "New Take". The gate fires inside
        // RootView.newTake() — the editor must NOT open; the paywall must.
        let addButton = app.descendants(matching: .any)
            .matching(identifier: "add-button").firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 2))
        addButton.tap()

        let newTake = app.descendants(matching: .any)
            .matching(identifier: "bloom-new-take").firstMatch
        XCTAssertTrue(newTake.waitForExistence(timeout: 2))
        newTake.tap()

        let sheet = app.descendants(matching: .any)
            .matching(identifier: "paywall-sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3),
                      "Add-while-lapsed must surface the paywall, not the editor.")
    }

    /// Restore Purchases is tappable from the paywall (Apple-mandatory element).
    func testPaywall_restorePurchasesIsTappable() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-lapsed"]
        app.launch()

        let restore = app.descendants(matching: .any)
            .matching(identifier: "paywall-restore").firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 3))
        XCTAssertTrue(restore.isHittable, "Restore Purchases must be tappable.")
    }
}
