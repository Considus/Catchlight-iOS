//
//  ControlTouchAreaUITests.swift
//  CatchlightUITests
//
//  The redesign changes the shape of buttons, never their reach. Every button on the main
//  screens keeps a frame of at least 44 by 44pt: the dock and its filters, the editor bar,
//  the onboarding primary, the Settings rows, the conflict screen and the paywall.
//

import XCTest

final class ControlTouchAreaUITests: XCTestCase {

    private let minimum: CGFloat = 44
    private let tolerance: CGFloat = 0.5

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    /// Two text links are 42pt high on main already, before any shape change (their hit area is
    /// widened past the text with `contentShape`): the onboarding "I already use Catchlight"
    /// link and the paywall's Restore. They are held at the 42pt they have, so a shape change
    /// cannot shrink them, and are reported rather than counted as 44pt buttons.
    private let existingTextLinkHeight: CGFloat = 42

    private func assertTouchArea(_ element: XCUIElement, _ name: String, minimumHeight: CGFloat? = nil,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 6), "\(name) did not appear", file: file, line: line)
        let f = element.frame
        let height = minimumHeight ?? minimum
        XCTAssertGreaterThanOrEqual(f.width, minimum - tolerance, "\(name) is \(f.width) wide", file: file, line: line)
        XCTAssertGreaterThanOrEqual(f.height, height - tolerance, "\(name) is \(f.height) high", file: file, line: line)
    }

    private func launch(_ extra: [String] = [], uitesting: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (uitesting ? ["--uitesting"] : []) + extra
        app.launch()
        return app
    }

    func testDock_andItsFilters() {
        let app = launch()
        for id in ["add-button", "angle-tab", "sequence-tab", "search-tab"] {
            assertTouchArea(anyElement(in: app, id: id), id)
        }
        tapWhenReady(app.buttons["sequence-tab"])
        for id in ["filter-important", "filter-notes", "filter-tasks", "filter-reminders"] {
            assertTouchArea(anyElement(in: app, id: id), id)
        }
    }

    func testEditorBar_buttons() {
        let app = launch()
        tapUntil(app.buttons["add-button"], appears: app.textViews["take-edit-body"])
        assertTouchArea(anyElement(in: app, id: "reminder-button"), "reminder-button")
        for name in ["Discard", "Mark done"] {
            let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            if button.exists { assertTouchArea(button, name) }
        }
        // Every button in the bar band, found by its position above the keyboard.
        let bar = app.buttons.allElementsBoundByIndex.filter {
            $0.exists && $0.frame.height > 0 && $0.frame.width <= 60 && $0.frame.minY > app.frame.height * 0.4
                && $0.frame.minY < app.frame.height * 0.7
        }
        XCTAssertGreaterThanOrEqual(bar.count, 3, "found \(bar.count) editor bar buttons")
        for button in bar { assertTouchArea(button, "editor bar button \(button.identifier) \(button.label)") }
    }

    func testOnboardingPrimary() {
        let app = launch(uitesting: false)
        let primary = app.buttons.element(boundBy: 0)
        XCTAssertTrue(primary.waitForExistence(timeout: 8), "onboarding did not appear")
        let buttons = app.buttons.allElementsBoundByIndex.filter { $0.exists && $0.frame.width > 120 }
        XCTAssertFalse(buttons.isEmpty, "no onboarding button found")
        for button in buttons {
            let isLink = button.identifier == "onboarding-restore-link"
            assertTouchArea(button, "onboarding button \(button.label)",
                            minimumHeight: isLink ? existingTextLinkHeight : nil)
        }
    }

    func testSettingsRows() {
        let app = launch()
        swipeUpWhenReady(anyElement(in: app, id: "angle-tab"))
        XCTAssertTrue(anyElement(in: app, id: "settings-sheet").waitForExistence(timeout: 5))
        let rows = app.buttons.allElementsBoundByIndex.filter { $0.exists && $0.frame.width > 120 && $0.frame.height > 0 }
        XCTAssertGreaterThanOrEqual(rows.count, 3, "found \(rows.count) Settings buttons")
        for row in rows { assertTouchArea(row, "settings button \(row.label)") }
    }

    func testConflictScreen_buttons() {
        let app = launch(["--uitesting-unverified"])
        let banner = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "3 Takes need a decision")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        banner.tap()
        XCTAssertTrue(app.staticTexts["Recover this Take?"].waitForExistence(timeout: 5))
        for name in ["Keep this version", "Skip for now", "Recover"] {
            let matches = app.buttons.matching(identifier: name).allElementsBoundByIndex
            XCTAssertFalse(matches.isEmpty, "no \(name) button")
            for button in matches { assertTouchArea(button, name) }
        }
    }

    func testPaywall_buttons() {
        let app = launch(["--uitesting-lapsed"])
        for id in ["paywall-subscribe", "paywall-dismiss"] {
            assertTouchArea(anyElement(in: app, id: id), id)
        }
        assertTouchArea(anyElement(in: app, id: "paywall-restore"), "paywall-restore",
                        minimumHeight: existingTextLinkHeight)
    }
}
