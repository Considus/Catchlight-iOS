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

    private func mark(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Catchlight'")).firstMatch
    }

    /// The step heading grows with the text size, and the logo and wordmark give their room to the
    /// content. Measured by the heading's height on a page whose heading is two lines at the
    /// default size (about 61pt): a heading that scales is several times that at the largest size.
    func testAtTheLargestSize_theHeadingScales_andTheLogoAndWordmarkAreGone() {
        continueAfterFailure = true
        let defaults = XCUIApplication()
        defaults.launchArguments = ["-appearanceMode", "night"]
        defaults.launch()
        XCTAssertTrue(mark(in: defaults).waitForExistence(timeout: 12), "the mark is missing at the default size")
        defaults.terminate()

        var checked = 0
        walkOnboarding(contentSize: largest) { step, app in
            XCTAssertFalse(mark(in: app).exists, "\(step): the logo and wordmark are still there")
            guard step == .basics else { return }
            let heading = app.staticTexts["A few things worth knowing"]
            XCTAssertTrue(heading.exists)
            XCTAssertGreaterThan(heading.frame.height, 150, "the heading did not scale: \(heading.frame.height)pt high")
            checked += 1
        }
        XCTAssertEqual(checked, 1)
    }

    /// A wrong guess on Confirm shows its message between the top of the screen and the heading:
    /// below the status bar, above "Confirm three words", and inside the screen. At the largest
    /// size the message is several lines of large text, so it needs more room than the gap
    /// above the heading gives it.
    func testAtTheLargestSize_theWrongGuessMessage_sitsBelowTheStatusBarAndAboveTheHeading() {
        continueAfterFailure = true
        var checked = 0
        walkOnboarding(contentSize: largest) { step, app in
            guard step == .confirm else { return }
            for _ in 0..<3 {
                let tile = app.buttons.allElementsBoundByIndex.first {
                    $0.exists && $0.isEnabled && $0.label != "Show my words once more" && !$0.label.isEmpty && !$0.label.hasPrefix("Word ")
                }
                guard let tile else { XCTFail("no bank tile to tap"); return }
                scrollUntilHittable(tile, in: app)
                tile.tap()
            }
            let message = app.staticTexts["Those aren't quite right. Try again."]
            XCTAssertTrue(message.waitForExistence(timeout: 6), "no wrong-guess message; on screen: " + app.descendants(matching: .any).allElementsBoundByIndex.filter { $0.exists }.map { "\($0.elementType.rawValue):\($0.label)" }.joined(separator: " | "))
            for _ in 0..<8 { app.swipeDown() }
            let heading = app.staticTexts["Confirm three words"]
            // The status bar and Dynamic Island take the top 62pt on iPhone 17.
            let top: CGFloat = 62
            XCTAssertGreaterThanOrEqual(message.frame.minY, top, "the message is under the status bar: \(message.frame)")
            XCTAssertLessThanOrEqual(message.frame.maxY, heading.frame.minY + 0.5,
                                     "the message overlaps the heading: \(message.frame) against \(heading.frame)")
            XCTAssertLessThanOrEqual(message.frame.maxX, app.frame.maxX + 0.5, "the message is clipped on the right")
            XCTAssertGreaterThanOrEqual(message.frame.minX, app.frame.minX - 0.5, "the message is clipped on the left")
            checked += 1
        }
        XCTAssertEqual(checked, 1)
    }
}
