//
//  SceneUITests.swift
//  CatchlightUITests
//
//  Choosing a Scene in Settings applies it the moment it is chosen: the open Settings
//  sheet repaints in the new Scene's ground and stays open. Measured on screen, by the
//  colour of a pixel in the sheet's margin, in both directions, so a stale or a cached
//  colour cannot pass.
//

import XCTest

final class SceneUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testChoosingAScene_repaintsTheOpenSettingsSheet_andKeepsItOpen() {
        let app = XCUIApplication()
        // Dark, from the argument domain, so the expected grounds are the Dark ones.
        app.launchArguments = ["--uitesting", "-appearanceMode", "night"]
        app.launch()

        swipeUpWhenReady(app.descendants(matching: .any).matching(identifier: "angle-tab").firstMatch)
        let sheet = app.descendants(matching: .any).matching(identifier: "settings-sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3), "Settings did not open")

        let picker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Scene")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "No Scene row in Settings")

        choose("Jade", from: picker, in: app)
        XCTAssertTrue(sheet.exists, "Settings closed when the Scene changed")
        XCTAssertEqual(picker.value as? String, "Jade")
        assertMarginIs(0x0C1511, "Jade Dark ground", in: app, sheet: sheet)

        choose("Cobalt", from: picker, in: app)
        XCTAssertTrue(sheet.exists, "Settings closed when the Scene changed")
        XCTAssertEqual(picker.value as? String, "Cobalt")
        assertMarginIs(0x0B0E2A, "Cobalt Dark ground", in: app, sheet: sheet)
    }

    /// Ten switches in one launch, cycling every Scene twice, with no pause beyond the
    /// colour check: each must repaint the open sheet. Every miss is listed, not only the first.
    /// Ten, not thirty: the first cycle shows each Scene repaints and the second shows a repeat
    /// switch does too, and the last twenty switches took 80 s of every CI run to say the same.
    func testManySwitches_eachRepaintsTheOpenSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-appearanceMode", "night"]
        app.launch()

        swipeUpWhenReady(app.descendants(matching: .any).matching(identifier: "angle-tab").firstMatch)
        let sheet = app.descendants(matching: .any).matching(identifier: "settings-sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3), "Settings did not open")
        let picker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Scene")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "No Scene row in Settings")

        let grounds: [(String, UInt32)] = [("Jade", 0x0C1511), ("Cobalt", 0x0B0E2A), ("Onyx", 0x05070A),
                                           ("Graphite", 0x111214), ("Tanzanite", 0x101028)]
        var misses: [String] = []
        for i in 0..<10 {
            let (name, ground) = grounds[i % grounds.count]
            choose(name, from: picker, in: app)
            if let miss = marginMismatch(ground, sheet: sheet) {
                misses.append("switch \(i + 1) to \(name): \(miss)")
            }
        }
        choose("Cobalt", from: picker, in: app)
        XCTAssertTrue(misses.isEmpty, "\(misses.count) of 10 switches left the sheet stale:\n" + misses.joined(separator: "\n"))
    }

    /// The editor's keyboard toolbar draws the chosen Scene, including after a switch made
    /// while a toolbar built for an earlier Scene already exists.
    func testEditorToolbar_drawsTheSceneChosenBeforeOpening() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-appearanceMode", "night"]
        app.launch()

        chooseFromClosedSettings("Jade", in: app)
        assertToolbarGround(0x0C1511, "Jade Dark ground", in: app)
        tapSaveCatcher(in: app, above: app.textViews["take-edit-body"])
        XCTAssertTrue(anyElement(in: app, id: "reminder-button").waitForNonExistence(timeout: 5), "editor stayed open")

        chooseFromClosedSettings("Onyx", in: app)
        assertToolbarGround(0x05070A, "Onyx Dark ground", in: app)
    }

    // MARK: - Helpers

    /// Open Settings with a swipe up from the dock's gap (a swipe on a button would also
    /// press it), choose `name`, and close the sheet.
    private func chooseFromClosedSettings(_ name: String, in app: XCUIApplication) {
        let tab = app.descendants(matching: .any).matching(identifier: "angle-tab").firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "No dock")
        let gap = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: tab.frame.maxX + 20, dy: tab.frame.midY))
        gap.press(forDuration: 0.05, thenDragTo: gap.withOffset(CGVector(dx: 0, dy: -150)))
        let sheet = app.descendants(matching: .any).matching(identifier: "settings-sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3), "Settings did not open")
        let picker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Scene")).firstMatch
        choose(name, from: picker, in: app)
        sheet.swipeDown(velocity: .fast)
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "Settings stayed open")
    }

    /// Open the seeded Take and read the toolbar's solid ground: 4pt in from the leading
    /// edge, 4pt below the Reminder button (the bar's last 8pt, past the fade).
    private func assertToolbarGround(_ expected: UInt32, _ label: String, in app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) {
        tapWhenReady(takeRow(in: app, withLabelStarting: "Buy film for the weekend shoot"))
        let reminder = anyElement(in: app, id: "reminder-button")
        XCTAssertTrue(reminder.waitForExistence(timeout: 5), "No editor toolbar", file: file, line: line)
        let point = CGPoint(x: 4, y: reminder.frame.maxY + 4)
        let e = (Int(expected >> 16 & 0xFF), Int(expected >> 8 & 0xFF), Int(expected & 0xFF))
        let deadline = Date().addingTimeInterval(3)
        var shot = XCUIScreen.main.screenshot()
        var drawn = (0, 0, 0)
        repeat {
            shot = XCUIScreen.main.screenshot()
            drawn = pixel(at: point, of: shot.image)
            if abs(drawn.0 - e.0) <= 3 && abs(drawn.1 - e.1) <= 3 && abs(drawn.2 - e.2) <= 3 { return }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "\(label): toolbar drew \(drawn)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("\(label): the toolbar drew \(drawn), expected \(e)", file: file, line: line)
    }

    /// Open the Scene menu and pick `name`. Each step waits for the control to take a tap, and the
    /// last waits for the menu to close: the next switch otherwise taps a picker that is still
    /// dismissing, which opens nothing ("Failed to not hittable: Button 'Scene'").
    private func choose(_ name: String, from picker: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(waitUntilHittable(picker), "The Scene row was not hittable")
        picker.tap()
        let item = app.buttons[name]
        XCTAssertTrue(waitUntilHittable(item), "The Scene menu did not open with \(name)")
        item.tap()
        XCTAssertTrue(item.waitForNonExistence(timeout: slowRunnerTimeout), "The Scene menu did not close after \(name)")
    }

    /// The pixel 6pt in from the sheet's leading edge, a third of the way down: the
    /// list's margin, where the sheet's ground shows.
    private func assertMarginIs(_ expected: UInt32, _ label: String, in app: XCUIApplication, sheet: XCUIElement,
                                file: StaticString = #filePath, line: UInt = #line) {
        if let miss = marginMismatch(expected, sheet: sheet) {
            XCTFail("\(label): \(miss)", file: file, line: line)
        }
    }

    /// Nil once the margin shows `expected` (polled for up to 3 s), else what it drew. A
    /// miss attaches the screen, so a failure can be read from the result bundle.
    private func marginMismatch(_ expected: UInt32, sheet: XCUIElement) -> String? {
        let deadline = Date().addingTimeInterval(3)
        var drawn = (0, 0, 0)
        var shot = XCUIScreen.main.screenshot()
        let e = (Int(expected >> 16 & 0xFF), Int(expected >> 8 & 0xFF), Int(expected & 0xFF))
        repeat {
            let point = CGPoint(x: sheet.frame.minX + 6, y: sheet.frame.minY + sheet.frame.height / 3)
            shot = XCUIScreen.main.screenshot()
            drawn = pixel(at: point, of: shot.image)
            if abs(drawn.0 - e.0) <= 3 && abs(drawn.1 - e.1) <= 3 && abs(drawn.2 - e.2) <= 3 { return nil }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "margin drew \(drawn), expected \(e)"
        attachment.lifetime = .keepAlways
        add(attachment)
        return "the sheet's margin drew \(drawn), expected \(e)"
    }

    private func pixel(at point: CGPoint, of image: UIImage) -> (Int, Int, Int) {
        guard let cg = image.cgImage else { return (-1, -1, -1) }
        var rgba = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let x = point.x * image.scale, y = point.y * image.scale
        context.draw(cg, in: CGRect(x: -x, y: y - CGFloat(cg.height) + 1,
                                    width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (Int(rgba[0]), Int(rgba[1]), Int(rgba[2]))
    }
}
