//
//  CloudStorageSettingsUITests.swift
//  CatchlightUITests — Task 6.13
//
//  Smoke-tests the Settings → Cloud Storage entry point. We do NOT drive the
//  real `UIDocumentPickerViewController` (it lives in a separate process and
//  is brittle under XCUITest); instead we confirm the row presents the
//  Catchlight-owned sub-sheet and can be dismissed without touching state.
//

import XCTest

final class CloudStorageSettingsUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testSettings_cloudStorageRow_opensSheetAndDismisses() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        // Open Settings via the dock swipe-up (owner redesign 2026-06-11 —
        // replaces the long-press on Dailies). Swiping up on any dock button
        // starts the drag on the toolbar, which is the gesture surface.
        let dailiesTab = app.descendants(matching: .any)
            .matching(identifier: "angle-tab").firstMatch
        swipeUpWhenReady(dailiesTab)

        let settingsSheet = app.descendants(matching: .any)
            .matching(identifier: "settings-sheet").firstMatch
        XCTAssertTrue(settingsSheet.waitForExistence(timeout: 3),
                      "Settings sheet should appear after the dock swipe-up.")

        // Locate and tap the Cloud Storage row. It lives in the System section (owner
        // 2026-06-21 — Sync folded into System), below Appearance + Security, so it
        // falls below the fold once those sections grow (e.g. the View/Order rows) —
        // and SwiftUI's lazy List keeps off-screen rows
        // OUT of the a11y tree. Scroll the settings list until the row is on screen
        // and hittable rather than assuming it's visible at rest.
        let cloudRow = app.descendants(matching: .any)
            .matching(identifier: "settings-cloud-storage").firstMatch
        var scrolls = 0
        while !cloudRow.isHittable && scrolls < 8 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(cloudRow.isHittable,
                      "Cloud Storage row should be reachable by scrolling the settings list.")
        cloudRow.tap()

        // The sub-sheet presents with the picker primary CTA visible.
        let chooseButton = app.buttons["Choose folder from Files"].firstMatch
        XCTAssertTrue(chooseButton.waitForExistence(timeout: 3),
                      "Cloud Storage sub-sheet should present.")

        // No Done button (owner 2026-06-21 — matches the About sheet). Dismiss by
        // dragging the sheet down from near its top (the drag indicator region)
        // to the bottom — leaves no state change behind.
        let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        XCTAssertTrue(settingsSheet.waitForExistence(timeout: 3),
                      "Settings sheet should still be visible after Cloud Storage dismisses.")
    }
}
