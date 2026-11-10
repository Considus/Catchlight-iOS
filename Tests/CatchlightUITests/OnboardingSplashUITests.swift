//
//  OnboardingSplashUITests.swift
//  CatchlightUITests
//
//  The launch splash draws the logo and wordmark at every text size, in the same place. The
//  launch screen and the lock screen draw them at every size, so a splash that dropped them at
//  the accessibility sizes would make them vanish and come back on a cold launch. Only the
//  onboarding steps drop the mark there.
//

import XCTest

final class OnboardingSplashUITests: XCTestCase {

    private func splashMark(contentSize: String?) -> CGRect? {
        let app = XCUIApplication()
        app.launchArguments = ["-appearanceMode", "night"]
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        app.launch()
        defer { app.terminate() }
        // The splash holds for 2.5s on a first launch.
        let mark = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Catchlight'")).firstMatch
        guard mark.waitForExistence(timeout: 2) else { return nil }
        return mark.frame
    }

    func testSplash_keepsTheMarkInTheSamePlace_atTheLargestSize() throws {
        let normal = try XCTUnwrap(splashMark(contentSize: nil), "no mark on the splash at the default size")
        let largest = try XCTUnwrap(splashMark(contentSize: "UICTContentSizeCategoryAccessibilityXXXL"),
                                    "no mark on the splash at the largest size")
        XCTAssertEqual(largest.minX, normal.minX, accuracy: 1, "the mark moved sideways")
        XCTAssertEqual(largest.minY, normal.minY, accuracy: 1, "the mark moved down or up")
        XCTAssertEqual(largest.width, normal.width, accuracy: 1, "the mark changed size")
    }
}
