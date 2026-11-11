//  The Dailies heading is the same size with an Obie pinned as without one.
//
//  Measured 2026-11-11 on an iPhone 17: with an Obie pinned, "Dailies" drew at 73.7 by 23pt,
//  against 99.7 by 30.7pt without an Obie (about 0.74 of its size). The heading block sits in a frame of
//  fixed height with a flexible page-colour fill below it, and the title, which may shrink to fit,
//  gave its height up to the fill.

import XCTest

final class ObieHeadingSizeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testDailiesTitle_isTheSameSize_withAnObiePinned() {
        let app = launchAppForUITesting()
        let title = app.staticTexts["Dailies"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Dailies heading not on screen")
        let alone = title.frame

        let row = takeRow(in: app, withLabelStarting: "Buy film")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Seeded Take not on the timeline")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).press(forDuration: 1.2)
        let makeObie = app.buttons["Make Obie"]
        XCTAssertTrue(makeObie.waitForExistence(timeout: 5), "Long-press menu did not appear")
        makeObie.tap()
        XCTAssertTrue(makeObie.waitForNonExistence(timeout: 5), "Long-press menu did not close")

        let pinned = settledFrame(of: app.staticTexts["Dailies"].firstMatch)
        XCTAssertEqual(pinned.width, alone.width, accuracy: 1,
                       "The Dailies title shrank with an Obie pinned (\(alone.width) → \(pinned.width)pt wide)")
        XCTAssertEqual(pinned.height, alone.height, accuracy: 1,
                       "The Dailies title shrank with an Obie pinned (\(alone.height) → \(pinned.height)pt tall)")
    }

    /// The element's frame once two reads a tenth of a second apart agree, so the pin animation
    /// has finished before the title is measured.
    private func settledFrame(of element: XCUIElement, timeout: TimeInterval = 5) -> CGRect {
        var last = element.frame
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            let now = element.frame
            if now == last { return now }
            last = now
        }
        return last
    }
}
