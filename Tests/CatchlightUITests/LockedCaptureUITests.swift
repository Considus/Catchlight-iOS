//
//  LockedCaptureUITests.swift
//  CatchlightUITests
//
//  Accessibility audit 2026-08, finding V2 — the locked-capture save route.
//  The only save affordance on `LockedCaptureView` is the tap-away catcher; if
//  it is not a real accessibility element, the only control VoiceOver / Voice
//  Control can reach is the toolbar ×, which DISCARDS the typed text.
//
//  `--uitesting-locked-capture` (Wiring.makeAppModel) seeds a locked model with
//  a blank pending capture, so the run lands on the screen directly — it is
//  otherwise unreachable under test (only a widget/intent hand-off on a locked
//  phone produces it).
//
//  Machine half of the verification only. The device half — Voice Control
//  "Show names" surfacing the control, and a sighted-free VoiceOver save —
//  is the owner's device test and cannot run on the simulator.
//

import XCTest

final class LockedCaptureUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchOnLockedCapture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-locked-capture"]
        app.launch()
        return app
    }

    /// V2: the save catcher must exist as a named accessibility element.
    /// Queried type-agnostically (`anyElement`): a SwiftUI
    /// `.accessibilityElement()` wrapper surfaces as `.other` on some runtimes
    /// and `.button` on others, so a type-pinned query would be runtime-fragile.
    func testSaveCatcher_isAccessibleWithLabel() {
        let app = launchOnLockedCapture()

        let save = anyElement(in: app, id: "locked-capture-save")
        XCTAssertTrue(save.waitForExistence(timeout: 5),
                      "locked-capture-save did not appear — the save route is invisible to assistive technology")
        XCTAssertEqual(save.label, "Save and close",
                       "The save catcher's accessibility label is the Voice Control name — it must read correctly")
    }

    /// The editor must still be present alongside the catcher — the full-screen
    /// element must not replace or swallow the editing surface.
    func testEditor_isStillReachableAlongsideSaveCatcher() {
        let app = launchOnLockedCapture()

        XCTAssertTrue(anyElement(in: app, id: "locked-capture-save").waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews["take-edit-body"].waitForExistence(timeout: 5),
                      "The editing surface must remain an accessibility element next to the save catcher")
    }
}
