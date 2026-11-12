//
//  SecondDeviceRestoreUITests.swift
//  CatchlightUITests
//
//  Settings > Second device: "Restore on this device" sits inline under the 12 word boxes. With
//  the keyboard up it can be scrolled into view, it stays disabled until all 12 words are in, and
//  it is half the Dailies toolbar's height (51.5pt).
//

import XCTest

final class SecondDeviceRestoreUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    // A valid 12-word phrase from the standard English list.
    private let words = Array(repeating: "abandon", count: 11) + ["about"]

    func testRestoreIsReachableWithTheKeyboardUp_andEnablesAfterTwelveWords() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-restore"]
        app.launch()
        let first = anyElement(in: app, id: "restore-word-1")
        XCTAssertTrue(first.waitForExistence(timeout: 12))
        Thread.sleep(forTimeInterval: 1)
        first.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard did not come up")

        let restore = anyElement(in: app, id: "second-device-restore")
        XCTAssertTrue(restore.exists)
        XCTAssertFalse(restore.isEnabled, "Restore should wait for all 12 words")
        XCTAssertEqual(restore.frame.height, 51.5, accuracy: 0.5, "Restore height")

        for (i, word) in words.enumerated() {
            let field = anyElement(in: app, id: "restore-word-\(i + 1)")
            scrollUntilVisibleAboveKeyboard(field, in: app)
            field.tap()
            field.typeText(word)
        }

        scrollUntilVisibleAboveKeyboard(restore, in: app)
        let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY
        XCTAssertLessThanOrEqual(restore.frame.maxY, keyboardTop, "Restore could not be scrolled above the keyboard")
        XCTAssertTrue(restore.isEnabled, "Restore stayed disabled after 12 words")
    }

    private func scrollUntilVisibleAboveKeyboard(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY
            if element.frame.maxY <= keyboardTop && element.frame.minY > 100 { return }
            let up = element.frame.maxY > keyboardTop
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.45 : 0.25))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.25 : 0.45))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
    }
}
