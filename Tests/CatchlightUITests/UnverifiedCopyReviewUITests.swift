//
//  UnverifiedCopyReviewUITests.swift
//  CatchlightUITests
//
//  The review sheet for cloud copies that failed verification (2026-09-30). The
//  `--uitesting-unverified` switch seeds one of each shape: both versions readable, only this
//  phone's version (the newer one elsewhere can't be read), and a Take only in the cloud.
//

import XCTest

final class UnverifiedCopyReviewUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-unverified"]
        app.launch()
        return app
    }

    private func openReview(_ app: XCUIApplication) {
        let banner = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "3 Takes need a decision")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "the banner names a decision, not a change")
        banner.tap()
        XCTAssertTrue(app.staticTexts["Recover this Take?"].waitForExistence(timeout: 5), "review sheet did not open")
    }

    func testReviewSheet_showsAllThreeShapes() {
        let app = launch()
        openReview(app)

        XCTAssertTrue(app.buttons["Keep this version"].exists, "both-versions card")
        XCTAssertTrue(app.buttons["Keep this phone's version"].exists, "unreadable-newer card")
        XCTAssertTrue(app.buttons["Recover"].exists, "cloud-only card")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "unverified-review"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testRecover_removesTheCardAndKeepsTheTake() {
        let app = launch()
        openReview(app)

        app.buttons["Recover"].tap()
        XCTAssertTrue(app.staticTexts["Recover this Take?"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Keep this phone's version"].exists, "the other cards stay")
    }
}
