//
//  NotificationStatusDotUITests.swift
//  CatchlightUITests
//
//  Settings > Notifications: Enabled shows a filled 8pt dot in the Scene's action colour, and
//  Disabled an 8pt ring with a 1.5pt line in the Scene's muted colour and nothing inside (owner
//  2026-11-12). Expected colours come from design/tokens.json, Cobalt (the default Scene).
//

import XCTest

final class NotificationStatusDotUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func rgb(_ hex: String) -> [Int] {
        let v = Int(hex.dropFirst(), radix: 16)!
        return [(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]
    }

    /// Opens Settings with the given notification state and returns the screenshot's pixels at
    /// the dot's centre, inside its line, and just outside it.
    private func sampleDot(state: String, mode: String) -> (centre: [Int], line: [Int], outside: [Int]) {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-notification-status", state, "-appearanceMode", mode]
        app.launch()
        let tab = anyElement(in: app, id: "angle-tab")
        XCTAssertTrue(tab.waitForExistence(timeout: 12))
        Thread.sleep(forTimeInterval: 0.8)
        tab.swipeUp()
        XCTAssertTrue(anyElement(in: app, id: "settings-sheet").waitForExistence(timeout: 5))
        let label = app.staticTexts[state == "on" ? "Enabled" : "Disabled"]
        var scrolls = 0
        while !(label.exists && label.isHittable) && scrolls < 10 { app.swipeUp(); scrolls += 1 }
        XCTAssertTrue(label.isHittable, "the Notifications row did not appear")
        Thread.sleep(forTimeInterval: 0.8)
        let image = XCUIScreen.main.screenshot().image
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            XCTFail("no screenshot"); return ([], [], [])
        }
        let scale = CGFloat(cg.width) / image.size.width
        let bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
        func px(_ x: CGFloat, _ y: CGFloat) -> [Int] {
            let o = Int(y * scale) * bpr + Int(x * scale) * bpp
            return (0..<3).map { Int(bytes[o + $0]) }
        }
        // The dot sits 6pt before the label and is 8pt across.
        let cx = label.frame.minX - 6 - 4, cy = label.frame.midY
        return (px(cx, cy), px(cx - 3.25, cy), px(cx - 9, cy))
    }

    private func assertClose(_ a: [Int], _ b: [Int], _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(zip(a, b).allSatisfy { abs($0 - $1) <= 14 }, "\(what): \(a) is not \(b)", file: file, line: line)
    }

    func testEnabledIsAFilledDotInTheActionColour() {
        assertClose(sampleDot(state: "on", mode: "daylight").centre, rgb("#2C41E8"), "light, Enabled centre")
        assertClose(sampleDot(state: "on", mode: "night").centre, rgb("#FF8AD0"), "dark, Enabled centre")
    }

    func testDisabledIsAHollowRingInTheMutedColour() {
        for (mode, muted) in [("daylight", "#4A5078"), ("night", "#AEB4E3")] {
            let s = sampleDot(state: "off", mode: mode)
            assertClose(s.line, rgb(muted), "\(mode), Disabled ring line")
            assertClose(s.centre, s.outside, "\(mode), Disabled ring is empty inside")
        }
    }
}
