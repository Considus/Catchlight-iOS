//
//  RefundRequestUITests.swift
//
//  Settings → Subscription → "Request a refund": the row is a full-size touch target,
//  and with no purchase on the test device it answers with a calm message instead of
//  opening Apple's sheet or doing nothing.
//

import XCTest

final class RefundRequestUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testSettings_requestRefundRow_is44ptAndExplainsWhenNothingToRefund() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        let dailiesTab = app.descendants(matching: .any)
            .matching(identifier: "angle-tab").firstMatch
        swipeUpWhenReady(dailiesTab)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "settings-sheet")
            .firstMatch.waitForExistence(timeout: 3))

        let row = app.descendants(matching: .any)
            .matching(identifier: "settings-request-refund").firstMatch
        var scrolls = 0
        while (!row.exists || !row.isHittable || row.frame.midY > app.frame.height * 0.6) && scrolls < 15 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50))
            from.press(forDuration: 0.05, thenDragTo: to)
            scrolls += 1
        }
        XCTAssertTrue(row.isHittable, "The refund row should be reachable in Settings.")
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        XCTAssertGreaterThanOrEqual(row.frame.width, 44)

        row.tap()
        let message = app.staticTexts["There's nothing to refund yet. A free trial isn't charged."]
        XCTAssertTrue(message.waitForExistence(timeout: 5),
                      "With no purchase, the row should say there is nothing to refund.")
    }
}
