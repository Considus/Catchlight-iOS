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

    // MARK: - Helpers

    private func choose(_ name: String, from picker: XCUIElement, in app: XCUIApplication) {
        tapWhenReady(picker)
        tapWhenReady(app.buttons[name])
    }

    /// The pixel 6pt in from the sheet's leading edge, a third of the way down: the
    /// list's margin, where the sheet's ground shows.
    private func assertMarginIs(_ expected: UInt32, _ label: String, in app: XCUIApplication, sheet: XCUIElement,
                                file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(3)
        var drawn = (0, 0, 0)
        var shot = XCUIScreen.main.screenshot()
        let e = (Int(expected >> 16 & 0xFF), Int(expected >> 8 & 0xFF), Int(expected & 0xFF))
        repeat {
            let point = CGPoint(x: sheet.frame.minX + 6, y: sheet.frame.minY + sheet.frame.height / 3)
            shot = XCUIScreen.main.screenshot()
            drawn = pixel(at: point, of: shot.image)
            if abs(drawn.0 - e.0) <= 3 && abs(drawn.1 - e.1) <= 3 && abs(drawn.2 - e.2) <= 3 { return }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        // Keep what the screen showed, so a failure can be read from the result bundle.
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "\(label) mismatch"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("\(label): the sheet's margin drew \(drawn), expected \(e)", file: file, line: line)
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
