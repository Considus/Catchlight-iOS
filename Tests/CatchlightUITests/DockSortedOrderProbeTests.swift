//
//  DockSortedOrderProbeTests.swift
//  CatchlightUITests
//
//  V40, remaining half. The in-app dump (`--a11y-order-dump`) walks the
//  UIAccessibility container protocol, which IS what VoiceOver enumerates and
//  therefore HAS sort priority applied — unlike XCUITest, which reads the view
//  hierarchy from outside.
//
//  🚨 It must run with an assistive technology ATTACHED. Launched by hand through
//  `simctl`, the walk returns 0 elements: without an AT client the accessibility
//  tree is never materialised, `isAccessibilityElement` is false everywhere, and
//  there is nothing to walk (measured 2026-09-09). XCUITest *is* an AT client, so
//  running the app under it is what makes the tree exist.
//
//  The dump lands in the app's diagnostics log; the harness reads it out of the
//  container afterwards. This test only has to get the app up and hold it there
//  long enough for the 3s dump to fire.
//

import XCTest

final class DockSortedOrderProbeTests: XCTestCase {

    /// 🚨 DIAGNOSTIC, NOT A REGRESSION TEST. It asserts nothing and it sleeps, so in CI
    /// it would cost every future PR time on both matrices and return no signal. Run it
    /// deliberately, with the `TEST_RUNNER_` prefix xcodebuild requires to forward it:
    ///
    ///     TEST_RUNNER_A11Y_PROBES=1 xcodebuild test -only-testing:...
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["A11Y_PROBES"] == "1",
                          "Diagnostic probe. Set A11Y_PROBES=1 to run it.")
    }

    private func run(step: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", step,
                               "--a11y-order-dump"]
        app.launch()
        XCTAssertTrue(app.buttons["add-button"].firstMatch.waitForExistence(timeout: 20),
                      "Dock did not load at step \(step)")
        // Touch the tree so the AX server definitely builds it, then hold past the dump.
        _ = app.descendants(matching: .any).allElementsBoundByIndex.count
        Thread.sleep(forTimeInterval: 6)
        _ = app.descendants(matching: .any).allElementsBoundByIndex.count
    }

    func testDumpSortedOrderWithAddHint()    { run(step: "1") }
    func testDumpSortedOrderWithoutAddHint() { run(step: "5") }
}

extension DockSortedOrderProbeTests {

    /// V40: the same dump WITH a pinned Obie. The bench had none and the owner's
    /// device always does. The Obie renders outside the `UIKitTimeline` collection,
    /// as a sibling — so it is the one named structural difference between the tree
    /// that shows the wrap and the tree that does not, and the collection's first
    /// cell is where his focus keeps landing.
    func testDumpSortedOrderWithObieAndAddHint() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", "1",
                               "--uitesting-obie", "--a11y-order-dump"]
        app.launch()
        XCTAssertTrue(app.buttons["add-button"].firstMatch.waitForExistence(timeout: 20),
                      "Dock did not load")
        _ = app.descendants(matching: .any).allElementsBoundByIndex.count
        Thread.sleep(forTimeInterval: 6)
        _ = app.descendants(matching: .any).allElementsBoundByIndex.count
    }
}

extension DockSortedOrderProbeTests {

    /// V40: a timeline long enough to SCROLL, so the collection recycles cells. The
    /// bench's two Takes never recycle; his always does. Cell reuse is the other
    /// named difference between the tree that shows the fault and the one that does
    /// not — and the destination is always the collection's FIRST cell, which is
    /// exactly where a recycled collection puts a reset cursor.
    func testDumpSortedOrderWithLongTimeline() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", "1",
                               "--uitesting-obie", "--uitesting-many", "30",
                               "--a11y-order-dump"]
        app.launch()
        XCTAssertTrue(app.buttons["add-button"].firstMatch.waitForExistence(timeout: 20),
                      "Dock did not load")
        _ = app.descendants(matching: .any).allElementsBoundByIndex.count
        Thread.sleep(forTimeInterval: 6)
        _ = app.descendants(matching: .any).allElementsBoundByIndex.count
    }
}

extension DockSortedOrderProbeTests {

    /// V40 §15at. The seventh capture falsified the condition every framing rested on:
    /// the ADD hint is not mounted at all. The owner is on tour step 2, and the hint up
    /// is "Tap the Iris to shape this Take." — so neither the pulse nor Add's frame
    /// could have been the cause, and the surviving condition is only "a hint is
    /// mounted".
    ///
    /// His focus log shows that hint sitting BETWEEN the Obie's Iris and the Obie's own
    /// card text, splitting one row's two elements apart. This asks whether that
    /// interleaving is real in VoiceOver's own order or only in the focus log —
    /// the distinction that has caught us four times.
    func testDumpSortedOrderAtStepTwoWithObie() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", "2",
                               "--uitesting-obie", "--a11y-order-dump"]
        app.launch()
        XCTAssertTrue(app.buttons["add-button"].firstMatch.waitForExistence(timeout: 20),
                      "Dock did not load")
        _ = app.descendants(matching: .any).allElementsBoundByIndex.count
        Thread.sleep(forTimeInterval: 6)
        _ = app.descendants(matching: .any).allElementsBoundByIndex.count
    }
}

extension DockSortedOrderProbeTests {

    /// 🚨 V45 (§15au). The owner completed the tour and CANNOT REACH ANY TAKE. His
    /// traversal is Dailies → Obie → dock, with all four ordinary Takes absent from
    /// the accessibility tree. Every real user is in this state: the tour runs once.
    ///
    /// The earlier step-5 dump DID vend the cells — but it had no pinned Obie. His
    /// device always has one. This is that exact comparison.
    func testTourCompleteWithObie_areTheCellsStillVended() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", "5",
                               "--uitesting-obie", "--a11y-order-dump"]
        app.launch()
        XCTAssertTrue(app.buttons["add-button"].firstMatch.waitForExistence(timeout: 20),
                      "Dock did not load")
        _ = app.descendants(matching: .any).allElementsBoundByIndex.count
        Thread.sleep(forTimeInterval: 6)
        _ = app.descendants(matching: .any).allElementsBoundByIndex.count
    }
}

extension DockSortedOrderProbeTests {

    /// 🚨 V45 candidate. `DailiesView` sets the timeline's `axHidden` to
    /// `ui.isEditingInPlace || ui.isFocusRingFanPresented`, and the pinned Obie never
    /// enters the collection — so if either flag stays set, EVERY Take leaves the
    /// accessibility tree while the Obie remains reachable. That is exactly the owner's
    /// symptom.
    ///
    /// Hint 2 instructs him to TAP THE IRIS, which opens the Focus-ring fan. This opens
    /// it and closes it, then reads the tree afterwards.
    func testFocusRingFan_doesNotStrandTheRowsHidden() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", "5",
                               "--uitesting-obie", "--a11y-order-dump"]
        app.launch()
        let iris = app.descendants(matching: .any).matching(identifier: "take-iris").firstMatch
        XCTAssertTrue(iris.waitForExistence(timeout: 20), "No Iris to tap")

        Thread.sleep(forTimeInterval: 4)          // let the resting dump land (tick 0)
        iris.tap()                                 // opens the Focus-ring fan

        // 🚨 ASSERT THE FAN OPENED. A first run of this test showed an identical tree at
        // every tick and would have read as "the fan does not strand the rows" — but the
        // tree was identical because the tap never opened anything. An interaction that
        // silently did not happen looks exactly like a clean negative.
        let blade = app.buttons["focus-ring-mark-task"]
        XCTAssertTrue(blade.waitForExistence(timeout: 8),
                      "The Iris tap did not open the Focus-ring fan, so this measures nothing.")
        Thread.sleep(forTimeInterval: 3)

        // Close it the way a finger does — the dim, near the top, clear of the marks.
        app.descendants(matching: .any).matching(identifier: "focus-ring-dim").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(blade.waitForNonExistence(timeout: 8), "The fan did not close.")
        Thread.sleep(forTimeInterval: 18)          // later ticks describe the state AFTER
        _ = app.buttons["add-button"].firstMatch.exists
    }
}

extension DockSortedOrderProbeTests {

    /// 🚨 V45 candidate, the OTHER half of `axHidden`: `ui.isEditingInPlace`.
    ///
    /// The Focus-ring fan is exonerated — it hides the rows while open (measured: 7
    /// elements, 0 cells) and restores them on close. The editor is the other driver,
    /// and the tour walks the owner straight into it: hint 1 says tap Add, which opens
    /// the editor. If the flag survives the editor closing, every Take stays out of the
    /// accessibility tree while the pinned Obie — which never enters the collection —
    /// stays reachable. That is his exact symptom.
    func testEditorClose_doesNotStrandTheRowsHidden() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", "5",
                               "--uitesting-obie", "--a11y-order-dump"]
        app.launch()
        let add = app.buttons["add-button"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20), "Dock did not load")
        Thread.sleep(forTimeInterval: 4)                    // resting dump (tick 0)

        // Assert the editor really opened — an interaction that silently did not happen
        // reads exactly like a clean negative.
        let body = app.textViews["take-edit-body"]
        tapUntil(add, appears: body)
        XCTAssertTrue(body.waitForExistence(timeout: 10),
                      "Add did not open the editor, so this measures nothing.")
        Thread.sleep(forTimeInterval: 3)

        // Close it the way a finger does: tap away, onto the heading.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        XCTAssertTrue(body.waitForNonExistence(timeout: 10), "The editor did not close.")
        Thread.sleep(forTimeInterval: 18)                   // later ticks describe AFTER
        _ = app.buttons["add-button"].firstMatch.exists
    }
}

extension DockSortedOrderProbeTests {

    /// 🚨 V45. The state no fixture has ever reached: a hint mounted and then REMOVED,
    /// in a process that has not restarted.
    ///
    /// `--uitesting-orientation-step` sets the step at launch, which reproduces only the
    /// owner's post-relaunch state — and that vends the cells normally here. His two
    /// no-hint sessions differ on both axes with the relaunch as the only difference:
    ///
    ///     tour completed in-session   Takes ABSENT   0 jumps
    ///     after a relaunch            Takes PRESENT  4 jumps
    ///
    /// This starts at step 1 with the hint up, then advances to complete in-process at
    /// 8s. The repeating dump brackets it: ticks before show the cells, ticks after say
    /// whether they survive the transition.
    func testTourCompletedInProcess_doTheCellsSurvive() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", "1",
                               "--uitesting-orientation-advance-to", "5", "8",
                               "--uitesting-obie", "--a11y-order-dump"]
        app.launch()
        XCTAssertTrue(app.buttons["add-button"].firstMatch.waitForExistence(timeout: 20),
                      "Dock did not load")
        Thread.sleep(forTimeInterval: 30)      // spans ticks either side of the advance
        _ = app.buttons["add-button"].firstMatch.exists
    }
}
