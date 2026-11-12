//
//  PageHeadingUITests.swift
//  CatchlightUITests
//
//  A page heading never breaks inside a word at any text size: it stays on one
//  line and scales down to fit. Measured as the heading's frame height against
//  the height of one line of its own font at that size.
//

import XCTest
import UIKit

final class PageHeadingUITests: XCTestCase {

    private static let sizes: [(name: String, category: String, ui: UIContentSizeCategory)] = [
        ("XXXL", "UICTContentSizeCategoryXXXL", .extraExtraExtraLarge),
        ("AX5", "UICTContentSizeCategoryAccessibilityXXXL", .accessibilityExtraExtraExtraLarge),
    ]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(_ category: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-appearanceMode", "daylight",
                               "-UIPreferredContentSizeCategoryName", category]
        app.launch()
        return app
    }

    /// One line of the 24pt heading (relative to title3) at `size`, as a ceiling:
    /// the line height of a font this big is under 1.25x its point size, and two
    /// lines are over 2x, so 1.7x separates them.
    private func singleLineCeiling(_ size: UIContentSizeCategory) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: size)
        let points = UIFontMetrics(forTextStyle: .title3).scaledValue(for: 24, compatibleWith: traits)
        return points * 1.7
    }

    private func assertOneLine(_ element: XCUIElement, _ name: String, _ size: (name: String, category: String, ui: UIContentSizeCategory)) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "\(name) heading not found at \(size.name)")
        let ceiling = singleLineCeiling(size.ui)
        XCTAssertLessThan(element.frame.height, ceiling,
                          "\(name) heading at \(size.name) is \(element.frame.height)pt tall, a single line is under \(ceiling)")
    }

    private func headingText(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }

    /// The "Dailies" title is its own element now (the date beside it is another), found by
    /// a case-insensitive match. It is measured by how much it GROWS against the default
    /// size: a second line would add a full line, which is over the ceiling's half. The
    /// ceiling is sized for the 24pt shared heading, a little under the 28pt title, which
    /// keeps the check strict.
    func testDailiesHeading_staysOneLine() {
        let base = launch("UICTContentSizeCategoryL")
        let baseHeight = headingText(base, "DAILIES")
        XCTAssertTrue(baseHeight.waitForExistence(timeout: 8))
        let defaultHeight = baseHeight.frame.height
        base.terminate()
        for size in Self.sizes {
            let app = launch(size.category)
            let heading = headingText(app, "DAILIES")
            XCTAssertTrue(heading.waitForExistence(timeout: 8), "Dailies heading not found at \(size.name)")
            let growth = heading.frame.height - defaultHeight
            XCTAssertLessThan(growth, singleLineCeiling(size.ui) / 2,
                              "Dailies heading at \(size.name) grew \(growth)pt over the default size: a second line")
            app.terminate()
        }
    }

    /// Dailies shows today's date beside its title, as drawn, and Sequence does not.
    func testDailiesHeading_showsTodaysDate_onlyOnDailies() {
        let app = launch("UICTContentSizeCategoryL")
        let date = app.staticTexts["dailies-date"]
        XCTAssertTrue(date.waitForExistence(timeout: 8), "No date beside the Dailies heading")
        // Built with a different API from the app's, so the test can't agree by construction.
        // The day carries its English ordinal ("12th"), which VoiceOver reads as one word.
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        let dayNumber = Calendar.current.component(.day, from: Date())
        let ordinal = NumberFormatter()
        ordinal.numberStyle = .ordinal
        ordinal.locale = Locale(identifier: "en")
        let expected = formatter.string(from: Date())
            .replacingOccurrences(of: "\\b\(dayNumber)\\b", with: ordinal.string(from: NSNumber(value: dayNumber))!,
                                  options: .regularExpression)
        XCTAssertEqual(date.label, expected)
        XCTAssertTrue(headingText(app, "Dailies").exists, "No Dailies title")

        app.buttons["sequence-tab"].tap()
        XCTAssertTrue(headingText(app, "SEQUENCE").waitForExistence(timeout: 5), "Sequence heading not shown")
        XCTAssertFalse(date.exists, "The date still shows in Sequence")
    }

    func testSettingsHeading_isOneLine() {
        for size in Self.sizes {
            let app = launch(size.category)
            let tab = anyElement(in: app, id: "angle-tab")
            XCTAssertTrue(tab.waitForExistence(timeout: 8))
            tab.swipeUp()
            XCTAssertTrue(anyElement(in: app, id: "settings-sheet").waitForExistence(timeout: 5))
            assertOneLine(headingText(app, "Settings"), "Settings", size)
            app.terminate()
        }
    }

    func testStoryboardHeading_isOneLine() throws {
        for size in Self.sizes {
            let app = launch(size.category)
            tapWhenReady(anyElement(in: app, id: "take-iris"))
            let taskMark = app.buttons["focus-row-mark-task"]
            try XCTSkipUnless(taskMark.waitForExistence(timeout: 3), "Focus row did not open")
            taskMark.tap()
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.12)).tap()
            try XCTSkipUnless(taskMark.waitForNonExistence(timeout: 3), "Focus row did not commit")
            tapWhenReady(app.buttons["angle-tab"])
            XCTAssertTrue(anyElement(in: app, id: "storyboard-row").waitForExistence(timeout: 5))
            assertOneLine(headingText(app, "STORYBOARD"), "Storyboard", size)
            app.terminate()
        }
    }
}
