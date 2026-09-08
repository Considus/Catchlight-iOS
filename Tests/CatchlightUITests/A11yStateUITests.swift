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

// MARK: - V16

/// V16: a Settings picker's NAME and its current SETTING must be separate.
///
/// The audit found the selection welded into the accessibility label, so
/// "Appearance mode" and "System" arrived as one string. That is not a wording
/// preference: VoiceOver re-reads only the VALUE when a control changes, so a
/// welded label announces nothing on change, and the control reads as a
/// different control depending on what it is set to.
///
/// The assertion that matters is the NEGATIVE one — the label must not contain
/// the value. A passing `value` alone would not catch a regression that set
/// both.
final class SettingsPickerValueUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAppearancePicker_speaksNameAndValueSeparately() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        // Settings opens on the dock swipe-up (owner redesign 2026-06-11); the
        // Appearance section is first, so this picker needs no scrolling.
        let dailiesTab = app.descendants(matching: .any)
            .matching(identifier: "angle-tab").firstMatch
        swipeUpWhenReady(dailiesTab)

        XCTAssertTrue(app.descendants(matching: .any)
                        .matching(identifier: "settings-sheet").firstMatch
                        .waitForExistence(timeout: 3),
                      "Settings sheet should appear after the dock swipe-up.")

        // Queried by LABEL rather than identifier, because the label is the thing
        // under test: if the weld came back the label would read "Appearance mode
        // System" and this exact match would stop resolving.
        let picker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Appearance mode")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5),
                      "No element is named exactly 'Appearance mode' — the value is "
                      + "welded back into the label (V16).")

        let value = picker.value as? String
        XCTAssertFalse((value ?? "").isEmpty,
                       "The Appearance picker states no value, so a VoiceOver user is "
                       + "never told the current setting (V16).")
        XCTAssertFalse(picker.label.contains(value ?? "\u{0}"),
                       "The label '\(picker.label)' still carries its value "
                       + "'\(value ?? "")' — the V16 weld has returned.")
    }
}
