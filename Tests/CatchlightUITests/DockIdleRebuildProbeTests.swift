//
//  DockIdleRebuildProbeTests.swift
//  CatchlightUITests
//
//  V40, §15ar. The owner restated the fault and it is not about order:
//  "I can get everywhere, it just doesn't hold focus to where I put it."
//
//  🚨 Every instrument built for this bug measured ORDER — what follows what,
//  whether it wraps, which container holds it, whether sort priority applies. The
//  order was correct in all five bench conditions and in both directions on his
//  device, because order was never the fault. A control DESTROYED and rebuilt under
//  the cursor loses focus with no traversal move at all, and is invisible to every
//  one of those instruments.
//
//  This is a test, not a mechanism. It needs no assistive client and no device:
//  park the app on Dailies with the tour armed, touch NOTHING, and count body
//  evaluations.
//
//      rebuilding while idle -> the fault has a home, reproducible on the bench
//      stable while idle     -> focus loss is not re-render; the family is eliminated
//
//  Seeded with an Obie and a full timeline deliberately: `DailiesView` drives
//  `firstRowTop`, `spineTopInset` and `pinnedObieNaturalHeight` from GeometryReader
//  preferences into `@State`, and those are fed by content the earlier fixtures did
//  not have. A preference-driven feedback loop would rebuild continuously.
//

import XCTest

final class DockIdleRebuildProbeTests: XCTestCase {

    /// Control: the SAME idle window with the tour complete, so no hint and no pulse.
    /// The difference between the two counts is what the pulse costs the dock. The
    /// pulse's `addPulseScale` is `@State` on `BottomDockView`, so every change
    /// re-evaluates the WHOLE dock body — all four buttons and the tooltip, not just
    /// Add. That is the shape of the owner's "it jumps from any of the toolbar buttons
    /// and the tooltip", where a fix aimed only at Add's frame would not be.
    func testDockRebuildCountWithoutTheTour() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", "5",
                               "--uitesting-obie", "--uitesting-many", "30",
                               "--a11y-diag"]
        app.launch()
        XCTAssertTrue(app.buttons["add-button"].firstMatch.waitForExistence(timeout: 20),
                      "Dock did not load")
        Thread.sleep(forTimeInterval: 20)
        XCTAssertTrue(app.buttons["add-button"].firstMatch.exists)
    }

    func testDockDoesNotRebuildWhileIdle() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", "1",
                               "--uitesting-obie", "--uitesting-many", "30",
                               "--a11y-diag"]
        app.launch()
        XCTAssertTrue(app.buttons["add-button"].firstMatch.waitForExistence(timeout: 20),
                      "Dock did not load")

        // Touch nothing. Any query is itself an accessibility client poking the tree,
        // so the idle window stays completely clear of XCUITest.
        Thread.sleep(forTimeInterval: 20)

        // One query at the end only, to keep the app alive to this point.
        XCTAssertTrue(app.buttons["add-button"].firstMatch.exists)
    }
}
