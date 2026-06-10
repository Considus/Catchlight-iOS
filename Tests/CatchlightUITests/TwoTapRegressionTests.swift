//
//  TwoTapRegressionTests.swift
//  CatchlightUITests
//
//  Workplan §7.5 — the two-tap rule regression anchor. Iterates the dock
//  buttons and asserts each primary destination is reachable in ONE interaction
//  (with the exception of "create a Take", which is two by design — Add bloom
//  + bloom option). This test fails immediately if navigation is restructured
//  in a way that violates the rule, even before the per-flow tests in
//  CoreFlowsUITests catch it functionally.
//
//  These are structural reachability assertions, NOT functional flow tests —
//  CoreFlowsUITests handles the full flows.
//

import XCTest

final class TwoTapRegressionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // Each dock destination gets its own test from a fresh launch — they are
    // structurally independent and easier to reason about than chaining
    // navigation in one method. The shared invariant: ONE interaction from
    // resting Dailies state reaches the destination.

    func testReachability_search_inOneTap() {
        let app = launchAppForUITesting()
        XCTAssertTrue(app.buttons["dailies-tab"].waitForExistence(timeout: 3))
        assertReachableInOneInteraction(
            "Search",
            interaction: { app.buttons["search-tab"].tap() },
            expectedElement: app.textFields["search-field"]
        )
    }

    func testReachability_sequence_inOneTap() {
        let app = launchAppForUITesting()
        XCTAssertTrue(app.buttons["dailies-tab"].waitForExistence(timeout: 3))
        // Sequences are saved searches (2026-06-10): with none kept yet, the
        // tab's resting state is the create-from-Search hint.
        assertReachableInOneInteraction(
            "Sequence",
            interaction: { app.buttons["sequence-tab"].tap() },
            expectedElement: app.descendants(matching: .any)
                .matching(identifier: "sequence-create-hint")
                .firstMatch
        )
    }

    func testReachability_settings_inOneLongPress() {
        let app = launchAppForUITesting()
        XCTAssertTrue(app.buttons["dailies-tab"].waitForExistence(timeout: 3))
        // The most-violated invariant historically — Settings keeps trying to
        // grow its own tab, which would push it OFF the two-tap path.
        assertReachableInOneInteraction(
            "Settings",
            interaction: { app.buttons["dailies-tab"].press(forDuration: 0.6) },
            expectedElement: app.navigationBars["Settings"]
        )
    }

    /// The Add → New Take pair is the one TWO-tap path in the dock — guard it
    /// with an explicit count so a future "wrap the editor in a confirmation
    /// step" change cannot quietly slip past CoreFlowsUITests.
    func testCreateTake_isExactlyTwoTaps() {
        let app = launchAppForUITesting()
        XCTAssertTrue(app.buttons["add-button"].waitForExistence(timeout: 3))

        // Tap 1.
        app.buttons["add-button"].tap()
        XCTAssertTrue(
            app.buttons["bloom-new-take"].waitForExistence(timeout: 2),
            "Add bloom did not appear in one tap"
        )

        // Tap 2.
        app.buttons["bloom-new-take"].tap()
        XCTAssertTrue(
            app.textViews["take-edit-body"].waitForExistence(timeout: 2),
            "Editor did not open in two taps"
        )
    }
}
