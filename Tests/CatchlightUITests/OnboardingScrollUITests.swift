//
//  OnboardingScrollUITests.swift
//  CatchlightUITests
//
//  At the largest accessibility text size an onboarding step is taller than the screen. Its
//  content scrolls under the pinned buttons, so the last of it can always be brought fully into
//  view above them. Measured on "A few things worth knowing", whose last point was cut off
//  behind Next.
//

import XCTest

final class OnboardingScrollUITests: XCTestCase {

    private let largest = "UICTContentSizeCategoryAccessibilityXXXL"

    func testWorthKnowing_atTheLargestSize_scrollsTheLastPointFullyAboveTheButton() {
        continueAfterFailure = true
        let lastSentence: [OnboardingStep: (text: String, button: String)] = [
            .basics: ("Tap the square in the corner of any Take to make it a task, set a reminder, or make it important.", "Next"),
            .basicsMore: ("Simply swipe up from the toolbar.", "Got it"),
        ]
        var checked = 0
        walkOnboarding(contentSize: largest) { step, app in
            guard let last = lastSentence[step] else { return }
            let body = app.staticTexts[last.text]
            let button = app.buttons[last.button]
            XCTAssertTrue(body.exists && button.exists, "\(step): the last point or its button is missing")
            for _ in 0..<8 where body.frame.maxY > button.frame.minY { app.swipeUp() }
            let screen = app.frame
            XCTAssertGreaterThanOrEqual(body.frame.minY, screen.minY, "\(step): the last point starts above the screen")
            XCTAssertLessThanOrEqual(body.frame.maxY, button.frame.minY + 0.5,
                                     "\(step): the last point is \(body.frame.maxY) down, behind the button at \(button.frame.minY)")
            checked += 1
        }
        XCTAssertEqual(checked, 2, "both pages should have been checked")
    }
}
