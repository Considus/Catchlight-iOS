//
//  SheetHeadingGapUITests.swift
//  CatchlightUITests
//
//  Every sheet keeps the same space under its heading: 16pt from the bottom of the heading's
//  line to the top of the first item, and 60pt to a lone centred state (the Privacy phrase
//  before it is revealed, an empty Notice History). Set by the Art Director, 2026-11-12.
//
//  A text item is measured by its frame. A card by its text's frame less the card's padding.
//  The icons are hidden from VoiceOver: About's (a filled square) is measured by its ink, and
//  a lone state's symbol through the line under it, as the symbol's height and the 16 between.
//  A sheet opens over Settings, whose rows carry the same names as the headings, so the heading
//  is the match nearest above the first item.
//

import XCTest
import UIKit

final class SheetHeadingGapUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-appearanceMode", "daylight",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"] + extra
        app.launch()
        return app
    }

    private func text(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }

    private func text(_ app: XCUIApplication, beginning prefix: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func openSettings(_ app: XCUIApplication) {
        swipeUpWhenReady(anyElement(in: app, id: "angle-tab"))
        XCTAssertTrue(anyElement(in: app, id: "settings-sheet").waitForExistence(timeout: 5))
    }

    /// Scrolls Settings with short drags until `row` can be tapped, then taps it.
    private func openRow(_ app: XCUIApplication, _ row: XCUIElement) {
        let sheet = anyElement(in: app, id: "settings-sheet")
        var drags = 0
        while !(row.exists && row.isHittable) && drags < 15 {
            let start = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            drags += 1
        }
        row.tap()
    }

    /// The bottom of the heading's line: the match for `label` whose bottom is nearest above `y`.
    private func headingBottom(_ app: XCUIApplication, _ label: String, above y: CGFloat) -> CGFloat? {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", label)).allElementsBoundByIndex
            .map(\.frame.maxY).filter { $0 <= y }.max()
    }

    private func assertGap(_ app: XCUIApplication, _ label: String, _ first: XCUIElement, _ expected: CGFloat,
                           _ name: String, inset: CGFloat = 0,
                           file: StaticString = #filePath, line: UInt = #line) {
        guard first.waitForExistence(timeout: 8) else {
            return XCTFail("\(name): first item not found", file: file, line: line)
        }
        let top = first.frame.minY - inset
        guard let bottom = headingBottom(app, label, above: top) else {
            return XCTFail("\(name): no heading above the first item", file: file, line: line)
        }
        let gap = top - bottom
        XCTAssertEqual(gap, expected, accuracy: 0.5, "\(name): \(gap)pt under the heading", file: file, line: line)
    }

    /// A lone centred state: `expected` from the heading to the symbol, then the symbol, then
    /// 16 to `lead`.
    private func assertLoneGap(_ app: XCUIApplication, _ label: String, symbol: String, lead: XCUIElement,
                               _ expected: CGFloat, _ name: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        guard lead.waitForExistence(timeout: 8),
              let bottom = headingBottom(app, label, above: lead.frame.minY),
              let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 40, weight: .regular)) else {
            return XCTFail("\(name): heading, symbol or line not found", file: file, line: line)
        }
        let gap = lead.frame.minY - 16 - image.size.height - bottom
        XCTAssertEqual(gap, expected, accuracy: 0.5, "\(name): \(gap)pt from the heading to the symbol", file: file, line: line)
    }

    private func assertInkGap(_ app: XCUIApplication, _ label: String, below marker: XCUIElement, _ expected: CGFloat,
                              _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        guard marker.waitForExistence(timeout: 8),
              let bottom = headingBottom(app, label, above: marker.frame.minY) else {
            return XCTFail("\(name): heading not found", file: file, line: line)
        }
        sleep(1)   // let the sheet settle before the screenshot
        guard let ink = firstInk(app, below: bottom) else {
            return XCTFail("\(name): no ink under the heading", file: file, line: line)
        }
        let gap = ink - bottom
        XCTAssertEqual(gap, expected, accuracy: 1.5, "\(name): \(gap)pt from the heading to the icon's ink", file: file, line: line)
    }

    /// The first row under `y` with a pixel that differs from the page colour at `y`, in points,
    /// across the middle half of the screen (the icons are centred).
    private func firstInk(_ app: XCUIApplication, below y: CGFloat) -> CGFloat? {
        guard let cg = app.screenshot().image.cgImage else { return nil }
        let scale = CGFloat(cg.width) / app.windows.firstMatch.frame.width
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let top = Int(y * scale) + 1
        let page = (top * width + width / 2) * 4
        for row in top..<min(height, top + Int(120 * scale)) {
            for x in (width / 4)..<(3 * width / 4) {
                let o = (row * width + x) * 4
                let d = abs(Int(pixels[o]) - Int(pixels[page])) + abs(Int(pixels[o + 1]) - Int(pixels[page + 1]))
                    + abs(Int(pixels[o + 2]) - Int(pixels[page + 2]))
                if d > 60 { return CGFloat(row) / scale }
            }
        }
        return nil
    }

    func testSettings() {
        let sheetLine = cloudStorageHeadingHeight()   // measured first: it launches the app itself
        let app = launch()
        openSettings(app)
        // The title is a list row, so VoiceOver's frame for it is the whole row: the top gap
        // (14) above the heading's line and the row's bottom inset (10) below it.
        let row = text(app, "Settings")
        let appearance = text(app, "Appearance")
        XCTAssertTrue(row.waitForExistence(timeout: 5) && appearance.waitForExistence(timeout: 5))
        let lineHeight = row.frame.height - 14 - 10
        XCTAssertEqual(lineHeight, sheetLine, accuracy: 0.5,
                       "Settings heading's line is \(lineHeight)pt, other sheets' are \(sheetLine)")
        let gap = appearance.frame.minY - (row.frame.maxY - 10)
        XCTAssertEqual(gap, 16, accuracy: 0.5, "Settings: \(gap)pt under the heading")
    }

    /// One line of the 34pt heading on a sheet whose heading is a plain text, at the default size.
    private func cloudStorageHeadingHeight() -> CGFloat {
        if Self.headingHeight == nil {
            let app = launch(["--uitesting-cloud-storage"])
            let lead = text(app, "Choose a cloud folder you own")
            if lead.waitForExistence(timeout: 8) {
                Self.headingHeight = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Cloud Storage"))
                    .allElementsBoundByIndex.filter { $0.frame.maxY <= lead.frame.minY }
                    .max { $0.frame.maxY < $1.frame.maxY }?.frame.height
            }
        }
        return Self.headingHeight ?? 0
    }
    private static var headingHeight: CGFloat?

    func testSyncConflicts() {
        let app = launch(["--uitesting-unverified"])
        let banner = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "3 Takes need a decision")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        banner.tap()
        assertGap(app, "Sync Conflicts", text(app, beginning: "The copies of these Takes"), 16, "Sync Conflicts")
    }

    func testAbout() {
        let app = launch()
        openSettings(app)
        openRow(app, app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "About")).firstMatch)
        let tagline = text(app, "Privacy-first notes and reminders")
        XCTAssertTrue(tagline.waitForExistence(timeout: 5), "About didn't open")
        assertInkGap(app, "About", below: tagline, 16, "About")
    }

    func testCloudStorage() {
        let app = launch(["--uitesting-cloud-storage"])
        assertGap(app, "Cloud Storage", text(app, "Choose a cloud folder you own"), 16, "Cloud Storage")
    }

    func testSecondDevice() {
        let app = launch(["--uitesting-restore"])
        // The first item is the warning card: its text sits 14 inside.
        assertGap(app, "Second device", text(app, beginning: "This replaces the account"), 16, "Second device", inset: 14)
    }

    func testPrivacyPhrase_beforeReveal() {
        let app = launch(["--uitesting-phrase"])
        assertLoneGap(app, "Privacy phrase", symbol: "faceid", lead: text(app, "Reveal your Privacy phrase"), 60, "Privacy phrase")
    }

    func testNoticeHistory_empty() {
        let app = launch()
        openSettings(app)
        openRow(app, anyElement(in: app, id: "settings-notice-history"))
        let clear = anyElement(in: app, id: "notice-history-clear")
        if clear.waitForExistence(timeout: 3) { clear.tap() }
        assertLoneGap(app, "Notice History", symbol: "bell.slash", lead: text(app, "No notices yet"), 60, "Notice History")
    }
}
