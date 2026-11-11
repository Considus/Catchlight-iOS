//
//  EditorIrisTapKeepsTakeUITests.swift
//  CatchlightUITests
//
//  Tapping the Iris of the Take being edited opens the Focus row. The Take must stay where it
//  was, in view, while the row is open (owner report 2026-11-11: it dropped back to its place
//  in the list and went under the veil, leaving only the Iris behind).
//

import XCTest

final class EditorIrisTapKeepsTakeUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testIrisTapWhileEditing_keepsTheTakeInPlace_onDailies() throws {
        try runScenario(inSequence: false)
    }

    func testIrisTapWhileEditing_keepsTheTakeInPlace_inSequence() throws {
        try runScenario(inSequence: true)
    }

    private func runScenario(inSequence: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-fill", "-appearanceMode", "daylight"]
        app.launch()
        XCTAssertTrue(app.buttons["add-button"].waitForExistence(timeout: 10), "Dock did not load")
        if inSequence { tapWhenReady(app.buttons["sequence-tab"]) }

        let body = app.textViews["take-edit-body"]
        let row = takeRow(in: app, withLabelStarting: "Filler Take 3")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Filler Take 3 not listed")
        tapUntil(row, appears: body)
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { body.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "No software keyboard")
        sleep(1)

        // The card's own Iris marks where the card is. The text inside is sealed from VoiceOver
        // while the row is open (on purpose), so it can't be measured then.
        let iris = anyElement(in: app, id: "editor-shape")
        XCTAssertTrue(iris.waitForExistence(timeout: 5))
        let before = iris.frame
        dump(app, "\(inSequence ? "seq" : "dailies")-before")

        iris.tap()
        XCTAssertTrue(app.buttons["focus-row-mark-task"].waitForExistence(timeout: 5), "Focus row did not open")
        sleep(2)
        dump(app, "\(inSequence ? "seq" : "dailies")-after")

        XCTAssertTrue(iris.exists, "The Take being edited is gone while the Focus row is open")
        let after = iris.frame
        print("[EDIT-IRIS] sequence=\(inSequence) card Iris before \(before) after \(after)")
        XCTAssertEqual(after.minY, before.minY, accuracy: 2, "The Take moved when its Iris was tapped")
        // A point on the card's own surface, right of the Iris and clear of its text.
        let onCard = CGPoint(x: after.maxX + 8, y: after.minY - 4)
        XCTAssertTrue(isDrawnUndimmed(app, at: onCard),
                      "The Take is under the veil while the Focus row is open")
    }

    private func dump(_ app: XCUIApplication, _ name: String) {
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
        }
    }

    /// The card fill under the veil is darker than the same fill drawn above it. Samples the
    /// point and reports whether it is close to the undimmed card colour (bright in Daylight).
    private func isDrawnUndimmed(_ app: XCUIApplication, at point: CGPoint) -> Bool {
        let image = XCUIScreen.main.screenshot().image
        guard let cg = image.cgImage else { return false }
        let scale = CGFloat(cg.width) / app.frame.width
        let x = Int(point.x * scale), y = Int(point.y * scale)
        guard x >= 0, y >= 0, x < cg.width, y < cg.height,
              let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return false }
        let o = y * cg.bytesPerRow + x * (cg.bitsPerPixel / 8)
        let luminance = (Int(bytes[o]) + Int(bytes[o + 1]) + Int(bytes[o + 2])) / 3
        print("[EDIT-IRIS] sample at \(point) luminance \(luminance)")
        return luminance > 200
    }
}
