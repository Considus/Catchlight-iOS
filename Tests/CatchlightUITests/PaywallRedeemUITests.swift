//
//  PaywallRedeemUITests.swift
//
//  "Redeem Code" is an outlined button directly under "Subscribe now", with its
//  one-line explanation beneath it, both on the first screen (no scrolling) on
//  the iPhone SE and the iPhone 17. "Restore Purchases" has its own line and
//  never breaks mid-word at the largest text size. Run on both phones.
//

import XCTest

final class PaywallRedeemUITests: XCTestCase {

    private let largest = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchPaywall(contentSize: String? = nil, mode: String = "daylight") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-lapsed", "-appearanceMode", mode]
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        app.launch()
        XCTAssertTrue(anyElement(in: app, id: "paywall-subscribe").waitForExistence(timeout: 10))
        return app
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    func testRedeemCode_isAButtonUnderSubscribe_andItsLineIsOnTheFirstScreen() {
        let app = launchPaywall()
        let subscribe = anyElement(in: app, id: "paywall-subscribe")
        let redeem = anyElement(in: app, id: "paywall-redeem")
        let note = anyElement(in: app, id: "paywall-redeem-note")
        XCTAssertTrue(redeem.waitForExistence(timeout: 5))
        XCTAssertTrue(note.exists, "the line under Redeem Code is missing")
        let screen = app.windows.firstMatch.frame
        // No scrolling: both are fully on the first screen.
        XCTAssertLessThanOrEqual(redeem.frame.maxY, screen.height, "Redeem Code is below the first screen")
        XCTAssertLessThanOrEqual(note.frame.maxY, screen.height - 8, "the line under Redeem Code is cut by the fold (maxY \(note.frame.maxY) of \(screen.height))")
        // A button as wide as Subscribe, directly beneath it, with its line under that.
        XCTAssertEqual(redeem.frame.width, subscribe.frame.width, accuracy: 1, "Redeem Code is not a full-width button")
        XCTAssertGreaterThanOrEqual(redeem.frame.minY, subscribe.frame.maxY)
        XCTAssertLessThanOrEqual(redeem.frame.minY - subscribe.frame.maxY, 24, "Redeem Code is not directly under Subscribe")
        XCTAssertGreaterThanOrEqual(note.frame.minY, redeem.frame.maxY)
        XCTAssertTrue(note.label.contains("extra free month"), "line was: \(note.label)")
        // Subscribing needs no extra tap: Subscribe is still the first thing a tap reaches.
        XCTAssertTrue(subscribe.isHittable)
    }

    func testRestorePurchases_atTheLargestSize_hasItsOwnLine_isNeverBrokenMidWord_andNothingIsClipped() {
        let app = launchPaywall(contentSize: largest)
        let screen = app.windows.firstMatch.frame
        let restore = anyElement(in: app, id: "paywall-restore")
        scrollTo(restore, in: app)
        XCTAssertTrue(restore.isHittable)
        // Whole words only: at this size the two words stack on two lines. A break inside
        // "Purchases" ("Purchase" over "s") is a third line: 184 high on main, 132 high as two lines.
        XCTAssertLessThan(restore.frame.height, 160, "Restore Purchases is \(restore.frame.height) high: it broke mid-word")
        for id in ["paywall-subscribe", "paywall-redeem", "paywall-redeem-note", "paywall-restore"] {
            let element = anyElement(in: app, id: id)
            scrollTo(element, in: app)
            XCTAssertTrue(element.exists, "\(id) is missing")
            XCTAssertGreaterThanOrEqual(element.frame.minX, 0, "\(id) is clipped at the left")
            XCTAssertLessThanOrEqual(element.frame.maxX, screen.width + 0.5, "\(id) is clipped at the right")
        }
    }
}
