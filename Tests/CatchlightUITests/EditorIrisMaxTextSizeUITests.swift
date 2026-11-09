//
//  EditorIrisMaxTextSizeUITests.swift
//  CatchlightUITests
//
//  At the largest accessibility text size, editing an EXISTING, long
//  Take with the software keyboard up, the editing card's Iris ("editor-shape")
//  was reported missing on device. The element can stay in the accessibility
//  tree while the heading mask paints over it, so existence alone proves
//  nothing. Each scenario checks the Iris frame sits inside the window and above
//  the keyboard, then samples the Iris's outline ring on screen: a drawn ring
//  differs from the card fill just inside it, a covered one does not.
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
        tapSaveCatcher(in: app, above: body)
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
                      "Software keyboard did not appear: this run cannot test the Iris text-size cap")
        sleep(1) // let the grow-up cap settle against the live keyboard top

        // 4. Measure the Iris.
        let irises = app.descendants(matching: .any).matching(identifier: "editor-shape")
        XCTAssertTrue(irises.firstMatch.waitForExistence(timeout: 5), "editor-shape not in the tree")
        let iris = irises.firstMatch
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "iris-max-text-editor-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let frame = iris.frame
        let window = app.windows.firstMatch.frame
        let edges = irisRingShares(of: frame, in: shot.image)
        let ring = edges.min() ?? 0
        let report = String(format: "[iris-max-text] \(name) iris=%@ keyboardTop=%.1f window=%@ ring=%.2f (top %.2f right %.2f bottom %.2f left %.2f)",
                            NSCoder.string(for: frame), keyboard.frame.minY,
                            NSCoder.string(for: window), ring,
                            edges[0], edges[1], edges[2], edges[3])
        print(report)
        let note = XCTAttachment(string: report)
        note.lifetime = .keepAlways
        add(note)

        XCTAssertTrue(window.contains(frame), "Editor Iris frame \(frame) is outside the window \(window)")
        XCTAssertLessThanOrEqual(frame.maxY, keyboard.frame.minY,
                                 "Editor Iris is under the keyboard (Iris bottom \(frame.maxY)pt, keyboard top \(keyboard.frame.minY)pt)")

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
        // Every edge is scored on its own, so a heading covering only part of the Iris fails too.
        // The ring is drawn in six lights with gaps between them, so a visible edge reads below
        // 100%. Measured on these scenarios: a visible edge reads 90% or more, so 50% splits it
        // from a covered one.
        XCTAssertGreaterThanOrEqual(ring, 0.5,
                                    "Editor Iris is hidden or partly covered: its weakest edge shows only \(Int(ring * 100))% of the outline ring (top \(Int(edges[0] * 100))%, right \(Int(edges[1] * 100))%, bottom \(Int(edges[2] * 100))%, left \(Int(edges[3] * 100))%)")
    }
}
