//
//  FirstRunTourUITests.swift
//  CatchlightUITests
//
//  D-259 / audit §15af — the WIRING of the first-run tour, not its state machine.
//
//  `FirstRunOrientationTests` has seven passing tests and every one exercises the state
//  machine: advance, persist, idempotence, out-of-order no-ops. Not one asserts that a hint
//  ever RENDERS. That is exactly why the tour could be dead after hint 1 for every user,
//  sighted or not, while the suite stayed green — hint 2's render site was gated on `isFirst`
//  inside a SwiftUI row that the UIKit timeline rewrite left called only once, with
//  `isFirst: false`. The machine advanced correctly to a step nothing could draw.
//
//  These tests assert the thing the machine cannot: that a step reaches the screen.
//

import XCTest

final class FirstRunTourUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch(atTourStep step: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", "\(step)"]
        app.launch()
        return app
    }

    /// Hint 2 must have a render site on the timeline. Before the D-259 fix this failed:
    /// the hint existed in the source but no call site could ever satisfy its gate.
    func testIrisHintReachesTheScreen() {
        let app = launch(atTourStep: 2)
        let hint = app.descendants(matching: .any)["orientation-iris-hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 15),
                      "Tour step 2 is set but hint 2 never rendered. The state machine can "
                      + "advance to a step with no render site — that is D-259.")
    }

    /// The seam must DISTINGUISH steps, or the test above proves nothing: a hint that
    /// rendered unconditionally would pass it. At step 1 the Iris hint must be absent.
    func testIrisHintIsAbsentAtTheStepBefore() {
        let app = launch(atTourStep: 1)
        let dock = app.descendants(matching: .any)["add-button"]
        XCTAssertTrue(dock.waitForExistence(timeout: 15), "Dock never appeared.")
        let hint = app.descendants(matching: .any)["orientation-iris-hint"]
        XCTAssertFalse(hint.exists,
                       "Hint 2 rendered at tour step 1. Its gate is not actually reading the "
                       + "step, so the test above would pass whatever the wiring did.")
    }
}
