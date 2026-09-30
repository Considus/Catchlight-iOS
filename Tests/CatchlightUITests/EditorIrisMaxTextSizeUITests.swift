//
//  EditorIrisMaxTextSizeUITests.swift
//  CatchlightUITests
//
//  ISSUE-005: at the largest accessibility text size, editing an EXISTING, long
//  Take with the software keyboard up, the editing card's Iris ("editor-shape")
//  was reported missing on device. The element can stay in the accessibility
//  tree while the heading mask paints over it, so existence alone proves
//  nothing: this test measures what share of the Iris's upper half (the part
//  that straddles the card's top edge, where the mask would cover it) actually
//  differs from the background colour on screen.
//

import XCTest

final class EditorIrisMaxTextSizeUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private static let maxSize = "UICTContentSizeCategoryAccessibilityXXXL"
    private static let largestStandardSize = "UICTContentSizeCategoryXXXL"
    private static let defaultSize = "UICTContentSizeCategoryL"

    func testEditorIris_isVisible_atMaxTextSize_withKeyboardUp_onLongExistingTake() throws {
        try runScenario(lineCount: 14, name: "long")
    }

    func testEditorIris_isVisible_atMaxTextSize_withKeyboardUp_onShortExistingTake() throws {
        try runScenario(lineCount: 1, name: "short")
    }

    /// With the "Created on" stamp showing (the owner's setting), it wraps onto several large lines
    /// at accessibility sizes and there is no room for it with the keyboard up, so it stands down
    /// while typing and the Iris must stay clear of the heading fade.
    func testEditorIris_isVisible_atMaxTextSize_withKeyboardUp_onLongExistingTake_withStamp() throws {
        try runScenario(lineCount: 14, name: "long-stamp", stamp: "editor", expectStamp: false)
    }

    func testEditorIris_isVisible_atMaxTextSize_withKeyboardUp_onShortExistingTake_withStamp() throws {
        try runScenario(lineCount: 1, name: "short-stamp", stamp: "editor", expectStamp: false)
    }

    /// Below the accessibility range the stamp keeps showing while typing.
    func testEditorIris_isVisible_atLargestStandardSize_withKeyboardUp_onLongExistingTake_withStamp() throws {
        try runScenario(lineCount: 14, name: "xxxl-long-stamp", size: Self.largestStandardSize,
                        stamp: "editor", expectStamp: true)
    }

    /// A notice strip above the page (here the quarantine notice) pushes the heading and its fade
    /// down; the editor card has to stop below where they actually are.
    func testEditorIris_isVisible_atMaxTextSize_withKeyboardUp_onLongExistingTake_withNoticeStrip() throws {
        try runScenario(lineCount: 14, name: "long-stamp-notice", stamp: "editor", expectStamp: false,
                        notice: true, expectNotice: false, maxIrisY: 250)
    }

    /// At the default size the notice strip stays up while typing, and the card stops below it.
    func testEditorIris_isVisible_atDefaultSize_withKeyboardUp_onLongExistingTake_withNoticeStrip() throws {
        try runScenario(lineCount: 14, name: "default-long-stamp-notice", size: Self.defaultSize,
                        stamp: "editor", expectStamp: true, notice: true, expectNotice: true)
    }

    /// Default size: the reference screenshot for "nothing moved" before and after the fix.
    func testEditorIris_isVisible_atDefaultSize_withKeyboardUp_onLongExistingTake_withStamp() throws {
        try runScenario(lineCount: 14, name: "default-long-stamp", size: Self.defaultSize,
                        stamp: "editor", expectStamp: true)
    }

    private func runScenario(lineCount: Int, name: String, size: String = maxSize,
                             stamp: String = "off", expectStamp: Bool? = nil,
                             notice: Bool = false, expectNotice: Bool? = nil,
                             maxIrisY: CGFloat? = nil) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting",
                               "-UIPreferredContentSizeCategoryName",
                               size,
                               "-catchlight.creationStamp", stamp]
            + (notice ? ["--uitesting-notice"] : [])
        app.launch()

        // 1. Make a long Take, then save it so the next open is an EXISTING Take.
        let addButton = app.buttons["add-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Dock did not load")
        let body = app.textViews["take-edit-body"]
        tapUntil(addButton, appears: body)
        let lines = (1...lineCount).map { "Line \($0) of a long existing Take" }
        typeWhenReady(body, lines.joined(separator: "\n"))
        tapWhenReady(anyElement(in: app, id: "dailies-save"))
        XCTAssertTrue(body.waitForNonExistence(timeout: 5), "Editor did not close on save")

        // 2. Re-open it: an existing Take, with its creation stamp.
        let row = takeRow(in: app, withLabelStarting: "Line 1")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Saved long Take not on the timeline")
        tapUntil(row, appears: body)
        // Only tap the text if the keyboard is not already up: a tap on existing text raises the
        // edit menu, which covers the card's corner in the screenshot.
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { body.tap() }

        // 3. The loop is only valid with the SOFTWARE keyboard up.
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5),
                      "Software keyboard did not appear: this run cannot test ISSUE-005")
        sleep(1) // let the grow-up cap settle against the live keyboard top

        // 4. Measure the Iris.
        let irises = app.descendants(matching: .any).matching(identifier: "editor-shape")
        XCTAssertTrue(irises.firstMatch.waitForExistence(timeout: 5), "editor-shape not in the tree")
        let iris = irises.firstMatch
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "issue-005-editor-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let frame = iris.frame
        let visible = visibleShareOfUpperHalf(of: frame, in: shot.image)
        let report = String(format: "[ISSUE-005] \(name) iris=%@ keyboardTop=%.1f window=%@ visibleUpperHalf=%.2f",
                            NSCoder.string(for: frame), keyboard.frame.minY,
                            NSCoder.string(for: app.windows.firstMatch.frame), visible)
        print(report)
        let note = XCTAttachment(string: report)
        note.lifetime = .keepAlways
        add(note)

        // A long Take should fill the room once the strip stands down. Measured: the Iris sits at
        // 169-172pt when the card is full height, and at 323pt when the card stayed at its floor.
        if let maxIrisY {
            XCTAssertLessThan(frame.minY, maxIrisY,
                              "Card did not grow into the room the strip left (Iris at \(frame.minY)pt)")
        }
        if let expectNotice {
            XCTAssertEqual(app.buttons["Dismiss quarantine notice"].exists, expectNotice,
                           "Notice strip \(expectNotice ? "should" : "should not") show while typing at this size")
        }
        if let expectStamp {
            let stampShown = app.staticTexts.allElementsBoundByIndex
                .contains { $0.label.hasPrefix("Created") }
            XCTAssertEqual(stampShown, expectStamp,
                           "Stamp \(expectStamp ? "should" : "should not") show while typing at this size")
        }
        // Measured on these scenarios: a hidden Iris reads 0-3%, a visible one 48-67% (the higher
        // figures include the dimmed timeline Iris showing faintly behind it), so 30% splits them.
        XCTAssertGreaterThanOrEqual(visible, 0.3,
                                    "Editor Iris is hidden: only \(Int(visible * 100))% of its upper half differs from the background")
    }

    /// Share of pixels in the inner square of the Iris's upper half that differ from the
    /// background colour, sampled just outside the Iris's top-left corner.
    private func visibleShareOfUpperHalf(of frame: CGRect, in image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0 }
        let scale = CGFloat(cg.width) / image.size.width
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let cx = min(max(x, 0), w - 1), cy = min(max(y, 0), h - 1)
            let i = (cy * w + cx) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
        let bg = rgb(Int((frame.minX - 2) * scale), Int((frame.minY - 2) * scale))

        let inset = frame.width * 0.2
        let x0 = Int((frame.minX + inset) * scale), x1 = Int((frame.maxX - inset) * scale)
        let y0 = Int((frame.minY + inset) * scale), y1 = Int(frame.midY * scale)
        guard x1 > x0, y1 > y0 else { return 0 }
        var differing = 0, total = 0
        for y in stride(from: y0, to: y1, by: 2) {
            for x in stride(from: x0, to: x1, by: 2) {
                let p = rgb(x, y)
                if abs(p.0 - bg.0) + abs(p.1 - bg.1) + abs(p.2 - bg.2) > 30 { differing += 1 }
                total += 1
            }
        }
        return total == 0 ? 0 : Double(differing) / Double(total)
    }
}
