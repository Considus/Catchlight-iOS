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

        // Locate the Cloud Storage row. It lives in the System section (owner 2026-06-21
        // — Sync folded into System), below Appearance + Security, so it falls below the
        // fold once those sections grow — and the D-110 Spotlight cell grew Security,
        // pushing it near the very bottom. SwiftUI's lazy List keeps off-screen rows OUT
        // of the a11y tree, so scroll it in.
        //
        // Then scroll it CLEAR OF THE BOTTOM EDGE before tapping: on the smaller iPhone 16
        // / iOS 26, a row that just came into view at the bottom is "hittable" but its tap
        // lands in the home-indicator dead zone and never presents the sheet (#114). Use
        // gentle 20%-screen drags (a full `swipeUp` overshoots on a short list) until the
        // row's centre sits in the upper ~55% of the window.
        let cloudRow = app.descendants(matching: .any)
            .matching(identifier: "settings-cloud-storage").firstMatch
        let safeMidY = app.frame.height * 0.55
        var scrolls = 0
        while (!cloudRow.isHittable || cloudRow.frame.midY > safeMidY) && scrolls < 15 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
            let to   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50))
            from.press(forDuration: 0.05, thenDragTo: to)
            scrolls += 1
        }
        XCTAssertTrue(cloudRow.isHittable,
                      "Cloud Storage row should be reachable by scrolling the settings list.")

        // Re-tap until the sub-sheet's primary CTA appears (belt-and-braces for iOS 26
        // tap timing), now that the row is comfortably clear of the bottom edge.
        let chooseButton = app.buttons["Choose folder from Files"].firstMatch
        tapUntil(cloudRow, appears: chooseButton, attempts: 4, timeout: 4)

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
