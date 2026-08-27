//
//  A11yStateUITests.swift
//  CatchlightUITests
//
//  Accessibility audit 2026-08, findings V10 and V11 (fix 6) — controls that
//  say what they are. V4's overdue/snoozed wording is unit-tested in
//  TakeRowViewTests (a pure static); these cover the two runtime halves
//  XCUITest can read: the Iris's button trait and the Important value flip.
//

import XCTest

final class A11yStateUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// V10: the scrolling row's Iris must carry the button trait — the audit
    /// measured it as `Other` while the pinned Obie row's Iris was `Button`.
    /// With the trait, a `.buttons` query resolves it.
    func testScrollingRowIris_announcesAsButton() {
        let app = launchAppForUITesting()
        XCTAssertTrue(anyElement(in: app, id: "take-iris").waitForExistence(timeout: 5),
                      "Timeline did not load")

        XCTAssertTrue(app.buttons.matching(identifier: "take-iris").firstMatch
                          .waitForExistence(timeout: 3),
                      "The scrolling row's Iris does not resolve as a button (V10)")
    }

    /// V11: the editor toolbar's Important button must speak its state as a
    /// value that flips on toggle — label stays fixed (the dock-filter pattern).
    func testImportantButton_valueFlipsOnToggle() {
        let app = launchAppForUITesting()
        let addButton = app.buttons["add-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Dock did not load")
        tapUntil(addButton, appears: app.textViews["take-edit-body"])

        let important = app.buttons["Important"].firstMatch
        XCTAssertTrue(important.waitForExistence(timeout: 5),
                      "Important button did not appear on the editor toolbar")

        let before = important.value as? String
        XCTAssertEqual(before, "off", "A fresh Take must announce Important as off")

        important.tap()
        // Re-query FRESH each poll — re-reading .value on the pre-tap element
        // reference pinned a stale snapshot on this runtime (measured 2026-08-20:
        // the bar visibly re-rendered to the on-state Ember tint while the held
        // reference kept answering "off"). Same class as the suite's other
        // race-hardening notes in UITestSupport.
        let deadline = Date().addingTimeInterval(3)
        var after = app.buttons["Important"].firstMatch.value as? String
        while after != "on", Date() < deadline {
            usleep(200_000)
            after = app.buttons["Important"].firstMatch.value as? String
        }
        XCTAssertEqual(after, "on",
                       "The Important value must flip when toggled (V11); got \(String(describing: after))")
    }
}
