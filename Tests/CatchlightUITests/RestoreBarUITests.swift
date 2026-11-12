//
//  RestoreBarUITests.swift
//  CatchlightUITests
//
//  Onboarding's restore step: with a word box focused and the keyboard up, the Restore and Back
//  buttons ride on a bar just above the keyboard, at half the Dailies toolbar's height.
//

import XCTest

final class RestoreBarUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testRestoreAndBackRideAboveTheKeyboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-appearanceMode", "daylight"]
        app.launch()
        let restoreLink = app.buttons["onboarding-restore-link"]
        XCTAssertTrue(restoreLink.waitForExistence(timeout: 12), "onboarding did not appear")
        Thread.sleep(forTimeInterval: 1)
        restoreLink.tap()
        let first = app.descendants(matching: .any).matching(identifier: "restore-word-1").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 8), "the restore step did not open")
        Thread.sleep(forTimeInterval: 1)
        first.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "the keyboard did not come up")
        Thread.sleep(forTimeInterval: 1)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "restore-step-keyboard-up"; shot.lifetime = .keepAlways; add(shot)

        let restore = app.descendants(matching: .any).matching(identifier: "restore-submit").firstMatch
        let back = app.descendants(matching: .any).matching(identifier: "restore-back").firstMatch
        XCTAssertTrue(restore.exists, "no Restore button with the keyboard up")
        XCTAssertTrue(back.exists, "no Back button with the keyboard up")
        XCTAssertLessThanOrEqual(restore.frame.maxY, keyboard.frame.minY + 0.5, "Restore is not above the keyboard")
        XCTAssertGreaterThan(restore.frame.maxY, keyboard.frame.minY - 80, "Restore is not on the keyboard")
        // Half the Dailies toolbar's height, like every bottom button outside it (owner 2026-11-11).
        XCTAssertEqual(restore.frame.height, 51.5, accuracy: 0.5, "Restore height")
        XCTAssertEqual(back.frame.height, 51.5, accuracy: 0.5, "Back height")
    }
}
