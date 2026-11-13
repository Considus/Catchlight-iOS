//
//  TouchTargetUITests.swift
//  CatchlightUITests
//
//  Every control that takes a touch is at least 44x44 pt (Apple's Human Interface Guidelines,
//  Accessibility > Mobility: default control size 44x44 pt on iOS). One audit per screen, by
//  `auditTouchTargets`, which measures the accessibility frame of each control. Run on the
//  default text size; the small iPhone is the one with the least room.
//

import XCTest

final class TouchTargetUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    /// The system date picker and the nav bar's own Cancel, Done and Clear are iOS controls of 36 to 38pt.
    /// Owner's decision, 12 Nov 2026: "Apple's controls stay as Apple intended". They are measured and
    /// logged, never failed, so this audit guards only the controls the app draws.
    private let systemPickerControls: Set<String> = ["Cancel", "Done", "Time Picker", "Month", "Previous Month",
                                                     "Next Month", "Show year picker", "Clear"]
    /// The strip buttons are rebuilt by the strip work (the new x), then held to 44 here.
    private let stripButtonsPendingRework: Set<String> = [
        "Dismiss quarantine notice", "Turn on notifications", "3 Takes need a decision. Double-tap to review.",
    ]

    private func launch(_ extra: [String] = [], uitesting: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (uitesting ? ["--uitesting"] : []) + extra
        app.launch()
        return app
    }

    private func settle(_ s: TimeInterval = 0.8) { Thread.sleep(forTimeInterval: s) }

    private func openSettings(_ app: XCUIApplication) {
        swipeUpWhenReady(anyElement(in: app, id: "angle-tab"))
        XCTAssertTrue(anyElement(in: app, id: "settings-sheet").waitForExistence(timeout: 5))
        settle()
    }

    private func scrollTo(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let el = anyElement(in: app, id: id)
        for _ in 0..<8 where !(el.exists && el.isHittable) { app.swipeUp() }
        return el
    }

    // MARK: Onboarding and unlock

    func testOnboarding_everyStep() {
        let app = XCUIApplication()
        app.launchArguments = ["-appearanceMode", "night"]
        app.launch()
        // The splash comes first; whatever buttons it has are measured too.
        for c in measureControls(in: app) { print("TA|onboarding-splash|\(c.type)|\(c.identifier)|\(c.label)|\(c.frame.width)|\(c.frame.height)") }
        walkOnboarding { step, app in
            auditTouchTargets("onboarding-\(step)", in: app)
        }
    }

    func testUnlock() {
        let app = launch(["--uitesting-locked"])
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 8))
        settle()
        auditTouchTargets("unlock", in: app)
    }

    func testLockedCapture() {
        let app = launch(["--uitesting-locked-capture"])
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 8))
        settle()
        auditTouchTargets("locked-capture", in: app)
    }

    // MARK: Dailies

    func testDailies_menuBarAndCards() {
        let app = launch(["--uitesting-fill"])
        XCTAssertTrue(anyElement(in: app, id: "add-button").waitForExistence(timeout: 8))
        settle()
        auditTouchTargets("dailies", in: app)
    }

    func testDailies_filters() {
        let app = launch()
        tapWhenReady(app.buttons["sequence-tab"])
        settle()
        auditTouchTargets("dailies-sequence-filters", in: app)
    }

    func testDailies_search() {
        let app = launch()
        tapWhenReady(app.buttons["search-tab"])
        settle()
        auditTouchTargets("dailies-search", in: app)
    }

    func testDailies_angle() {
        let app = launch()
        tapWhenReady(app.buttons["angle-tab"])
        XCTAssertTrue(anyElement(in: app, id: "storyboard-close").waitForExistence(timeout: 6), "Storyboard did not open")
        settle(1.2)
        auditTouchTargets("storyboard", in: app)
    }

    func testDailies_noticeStrip() {
        let app = launch(["--uitesting-notice"])
        XCTAssertTrue(anyElement(in: app, id: "add-button").waitForExistence(timeout: 8))
        settle()
        auditTouchTargets("dailies-notice-strip", in: app, allowing: stripButtonsPendingRework)
    }

    func testDailies_notificationsStrip() {
        let app = launch(["--uitesting-notifications-off"])
        XCTAssertTrue(anyElement(in: app, id: "reminders-silenced-turn-on").waitForExistence(timeout: 8))
        settle()
        auditTouchTargets("dailies-notifications-strip", in: app, allowing: stripButtonsPendingRework)
    }

    func testDailies_focusRow() {
        let app = launch()
        let iris = anyElement(in: app, id: "take-iris")
        XCTAssertTrue(iris.waitForExistence(timeout: 8))
        iris.tap()
        settle(1.2)
        auditTouchTargets("dailies-focus-row", in: app)
    }

    func testDailies_withAnObie() {
        let app = launch()
        let row = takeRow(in: app, withLabelStarting: "Buy film")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).press(forDuration: 1.2)
        let makeObie = app.buttons["Make Obie"]
        XCTAssertTrue(makeObie.waitForExistence(timeout: 5))
        makeObie.tap()
        XCTAssertTrue(makeObie.waitForNonExistence(timeout: 5))
        settle(1.2)
        auditTouchTargets("dailies-obie", in: app)
    }

    // MARK: Editors

    func testEditor_andReminderEditors() {
        let app = launch()
        tapUntil(app.buttons["add-button"], appears: app.textViews["take-edit-body"])
        settle()
        auditTouchTargets("editor", in: app)
        let reminder = anyElement(in: app, id: "reminder-button")
        tapWhenReady(reminder)
        settle(1.2)
        auditTouchTargets("editor-time-reminder", in: app, allowing: systemPickerControls)
        let mode = anyElement(in: app, id: "reminder-mode")
        if mode.exists {
            let place = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'place' OR label CONTAINS[c] 'location'")).firstMatch
            if place.waitForExistence(timeout: 2) { place.tap(); settle(1.2) }
            auditTouchTargets("editor-place-reminder", in: app, allowing: systemPickerControls)
        }
    }

    // MARK: Settings

    func testSettings_andSubscreens() {
        let app = launch()
        openSettings(app)
        auditTouchTargets("settings", in: app)
        app.swipeUp(); settle()
        auditTouchTargets("settings-scrolled", in: app)
    }

    func testSettings_noticeHistoryAndAbout() {
        let app = launch()
        openSettings(app)
        let history = scrollTo("settings-notice-history", in: app)
        XCTAssertTrue(history.exists)
        history.tap(); settle(1.2)
        auditTouchTargets("notice-history", in: app, allowing: systemPickerControls)
        app.swipeDown(velocity: .fast); settle()
        let about = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'About'")).firstMatch
        for _ in 0..<8 where !(about.exists && about.isHittable) { app.swipeUp() }
        XCTAssertTrue(about.exists, "no About row")
        about.tap(); settle(1.2)
        auditTouchTargets("about", in: app)
    }

    func testSettings_cloudStorage() {
        let app = launch(["--uitesting-cloud-storage"])
        XCTAssertTrue(anyElement(in: app, id: "cloud-sync-now").waitForExistence(timeout: 8)
                      || app.buttons.firstMatch.waitForExistence(timeout: 8))
        settle()
        auditTouchTargets("cloud-storage", in: app)
    }

    func testSettings_phrase() {
        let app = launch(["--uitesting-phrase"])
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 8))
        settle()
        auditTouchTargets("phrase-prompt", in: app)
    }

    func testSettings_phraseRevealed() {
        let app = launch(["--uitesting-phrase", "--uitesting-phrase-revealed"])
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 8))
        settle()
        auditTouchTargets("phrase-revealed", in: app)
    }

    func testSecondDevice() {
        let app = launch(["--uitesting-restore"])
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 8))
        settle()
        auditTouchTargets("second-device", in: app)
    }

    func testPaywall() {
        let app = launch(["--uitesting-lapsed"])
        XCTAssertTrue(anyElement(in: app, id: "paywall-subscribe").waitForExistence(timeout: 8))
        settle()
        auditTouchTargets("paywall", in: app)
        // The footer is below the fold on the small iPhone: scroll to it and measure that too.
        // Found by label whatever type the runtime gives a Link (a link on one iOS, a button or
        // text on another), so the check does not depend on it.
        func footer(_ label: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        }
        let terms = footer("Terms of Service")
        for _ in 0..<8 where !(terms.exists && terms.isHittable) { app.swipeUp() }
        XCTAssertTrue(terms.exists, "the paywall footer links were not reached")
        settle()
        for label in ["Privacy Policy", "Terms of Service", "Restore Purchases", "Redeem Code"] {
            let element = footer(label)
            XCTAssertTrue(element.exists, "\(label) is not on the paywall")
            XCTAssertGreaterThanOrEqual(element.frame.height, touchTargetMinimum - 0.5, "\(label) is \(element.frame.height) high")
            XCTAssertGreaterThanOrEqual(element.frame.width, touchTargetMinimum - 0.5, "\(label) is \(element.frame.width) wide")
        }
        auditTouchTargets("paywall-footer", in: app)
    }

    func testConflict() {
        let app = launch(["--uitesting-unverified"])
        let banner = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "3 Takes need a decision")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        auditTouchTargets("conflict-banner", in: app, allowing: stripButtonsPendingRework)
        banner.tap()
        XCTAssertTrue(app.staticTexts["Recover this Take?"].waitForExistence(timeout: 5))
        settle()
        auditTouchTargets("conflict-screen", in: app)
    }

    func testConflict_converted() {
        let app = launch(["--uitesting-converted"])
        let banner = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Takes changed' OR label CONTAINS 'Take changed' OR label CONTAINS 'need'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        banner.tap()
        settle(1.2)
        auditTouchTargets("conflict-converted", in: app)
    }
}
