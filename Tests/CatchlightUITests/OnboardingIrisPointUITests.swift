//
//  OnboardingIrisPointUITests.swift
//  CatchlightUITests
//
//  The Iris point on the first page of "A few things worth knowing" is drawn on screen as the
//  new sentence, naming the square in the corner of a Take, and the old wording is gone.
//

import XCTest

final class OnboardingIrisPointUITests: XCTestCase {

    func testIrisPoint_showsTheSquareSentence_notTheCircleOne() {
        continueAfterFailure = true
        walkOnboarding { step, app in
            guard step == .basics else { return }
            let square = app.staticTexts["Tap the square in the corner of any Take to make it a task, set a reminder, or make it important."]
            XCTAssertTrue(square.exists, "the Iris point does not show the new sentence")
            let circle = app.staticTexts["Tap the circle beside any Take to make it a task, set a reminder, or make it important."]
            XCTAssertFalse(circle.exists, "the Iris point still shows the old sentence")
        }
    }
}
