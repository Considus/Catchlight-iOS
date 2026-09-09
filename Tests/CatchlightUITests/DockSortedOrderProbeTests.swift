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
    /// deliberately:  A11Y_PROBES=1 xcodebuild test -only-testing:...
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
