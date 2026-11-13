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

    private func launch(_ category: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-appearanceMode", "daylight",
                               "-UIPreferredContentSizeCategoryName", category] + extra
        app.launch()
        return app
    }

    /// One line of the 34pt heading (relative to Large Title, capped at AX1 as the heading
    /// is) at `size`, as a ceiling: the line height of a font this big is under 1.25x its
    /// point size, and two lines are over 2x, so 1.7x separates them.
    private func singleLineCeiling(_ size: UIContentSizeCategory) -> CGFloat {
        let capped = size > .accessibilityMedium ? UIContentSizeCategory.accessibilityMedium : size
        let traits = UITraitCollection(preferredContentSizeCategory: capped)
        let points = UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: 34, compatibleWith: traits)
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
    /// size: a second line would add a full line, which is over the ceiling's half. Dailies
    /// and the shared heading are both 34pt.
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
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        XCTAssertEqual(date.label, formatter.string(from: Date()))
        XCTAssertTrue(headingText(app, "Dailies").exists, "No Dailies title")

        app.buttons["sequence-tab"].tap()
        XCTAssertTrue(headingText(app, "Sequence").waitForExistence(timeout: 5), "Sequence heading not shown")
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
            let dailies = headingText(app, "Dailies")
            XCTAssertTrue(dailies.waitForExistence(timeout: 8))
            let origin = dailies.frame.origin
            tapWhenReady(anyElement(in: app, id: "take-iris"))
            let taskMark = app.buttons["focus-row-mark-task"]
            try XCTSkipUnless(taskMark.waitForExistence(timeout: 3), "Focus row did not open")
            taskMark.tap()
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.12)).tap()
            try XCTSkipUnless(taskMark.waitForNonExistence(timeout: 3), "Focus row did not commit")
            tapWhenReady(app.buttons["angle-tab"])
            XCTAssertTrue(anyElement(in: app, id: "storyboard-row").waitForExistence(timeout: 5))
            let heading = headingText(app, "Storyboard")
            assertOneLine(heading, "Storyboard", size)
            // It starts where the Dailies title does: the × beside it doesn't push it down.
            XCTAssertEqual(heading.frame.minX, origin.x, accuracy: 0.5, "Storyboard heading's left edge at \(size.name)")
            XCTAssertEqual(heading.frame.minY, origin.y, accuracy: 0.5, "Storyboard heading's top at \(size.name)")
            // The × keeps its 44pt tap area.
            XCTAssertGreaterThanOrEqual(app.buttons["storyboard-close"].frame.height, 43.5, "the × tap area at \(size.name)")
            app.terminate()
        }
    }

    /// On a sheet the heading is centred (owner 2026-11-12: Settings and Sync Conflicts "should
    /// be centred"), at the same height as the Dailies title: the same distance below the
    /// sheet's top edge as Dailies' below the safe area, 14pt (`pageHeadingTopGap`). Where a
    /// sheet starts depends on the iOS version: on an iPhone 16 it is the safe area (59) on
    /// iOS 27, and 10pt lower (69) on iOS 18.5, which shrinks the page behind it (measured on
    /// both, 2026-11-13). So the sheet's top is measured, never taken as the safe area's.
    func testSheetHeadings_areCentred_atTheDailiesTitlesHeight() {
        let topGap: CGFloat = 14

        // Sync Conflicts.
        let app = launch("UICTContentSizeCategoryL", extra: ["--uitesting-unverified"])
        let banner = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "3 Takes need a decision")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        banner.tap()
        let conflicts = headingText(app, "Sync Conflicts")
        XCTAssertTrue(conflicts.waitForExistence(timeout: 5))
        let centre = app.windows.firstMatch.frame.midX
        XCTAssertEqual(conflicts.frame.midX, centre, accuracy: 1, "Sync Conflicts heading's centre")
        // The sheet's scroll view fills it, so its top is the sheet's.
        let sheetTop = app.scrollViews.firstMatch.frame.minY
        XCTAssertEqual(conflicts.frame.minY - sheetTop, topGap, accuracy: 0.5,
                       "Sync Conflicts heading's top, below the sheet's top at \(sheetTop)")
        app.terminate()

        // Settings: the title row starts at the sheet's top edge with no list margin above it;
        // the title is a list row, so its centre is measured by its ink.
        let settings = launch("UICTContentSizeCategoryL")
        swipeUpWhenReady(anyElement(in: settings, id: "angle-tab"))
        let sheet = anyElement(in: settings, id: "settings-sheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let row = headingText(settings, "Settings")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.frame.minY, sheet.frame.minY, accuracy: 0.5, "Settings title row's top")
        sleep(1)
        guard let span = inkSpan(settings, top: row.frame.minY + 10, bottom: row.frame.minY + 40) else {
            return XCTFail("no ink for the Settings title")
        }
        XCTAssertEqual((span.lowerBound + span.upperBound) / 2, centre, accuracy: 1.5,
                       "Settings title's ink runs \(span), not centred on \(centre)")
    }

    /// The left and right edges of the dark ink between `top` and `bottom`, in points.
    private func inkSpan(_ app: XCUIApplication, top: CGFloat, bottom: CGFloat) -> ClosedRange<CGFloat>? {
        guard let cg = app.screenshot().image.cgImage else { return nil }
        let scale = CGFloat(cg.width) / app.windows.firstMatch.frame.width
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var low = Int.max, high = Int.min
        for y in Int(top * scale)..<Int(bottom * scale) {
            for x in 0..<width {
                let o = (y * width + x) * 4
                let luma = (Int(pixels[o]) * 3 + Int(pixels[o + 1]) * 6 + Int(pixels[o + 2])) / 10
                if luma < 100 { low = min(low, x); high = max(high, x) }
            }
        }
        return low <= high ? CGFloat(low) / scale...CGFloat(high) / scale : nil
    }

    /// Where the first letter's ink starts, in points from the top: the first row with dark
    /// ink in a band from `x` to `x + 20`, below the status bar and clear of the camera.
    private func inkTop(_ app: XCUIApplication, x: CGFloat) -> CGFloat? {
        guard let cg = app.screenshot().image.cgImage else { return nil }
        let scale = CGFloat(cg.width) / app.windows.firstMatch.frame.width
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        for y in Int(45 * scale)..<Int(200 * scale) {
            for px in Int(x * scale)..<Int((x + 20) * scale) {
                let o = (y * width + px) * 4
                let luma = (Int(pixels[o]) * 3 + Int(pixels[o + 1]) * 6 + Int(pixels[o + 2])) / 10
                if luma < 100 { return CGFloat(y) / scale }
            }
        }
        return nil
    }

    /// Sequence and Search draw their title in Dailies' own slot. Their title isn't an element
    /// of its own (it carries the way back to Dailies), so its first letter's ink is measured
    /// against the Dailies title's, in Daylight. "D" and "S" differ by under half a point.
    func testSequenceAndSearchTitles_sitWhereTheDailiesTitleDoes() {
        let app = launch("UICTContentSizeCategoryL")
        let dailies = headingText(app, "Dailies")
        XCTAssertTrue(dailies.waitForExistence(timeout: 8))
        sleep(1)
        let x = dailies.frame.minX
        guard let reference = inkTop(app, x: x) else { return XCTFail("no ink for the Dailies title") }
        for (tab, title) in [("sequence-tab", "Sequence"), ("search-tab", "Search")] {
            tapWhenReady(app.buttons[tab])
            XCTAssertTrue(headingText(app, title).waitForExistence(timeout: 5), "\(title) heading not shown")
            sleep(1)
            guard let top = inkTop(app, x: x) else { XCTFail("no ink for \(title)"); continue }
            XCTAssertEqual(top, reference, accuracy: 1, "\(title)'s first letter starts at \(top), Dailies' at \(reference)")
            app.terminate()
            app.launch()
            XCTAssertTrue(dailies.waitForExistence(timeout: 8))
        }
    }
}
