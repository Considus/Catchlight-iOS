//
//  OnboardingWalk.swift
//  CatchlightUITests
//
//  A walk through first-run onboarding in English, down the Local path, so a test can look at
//  every step: Welcome, Restore, where Takes live, the Local warning, the Privacy phrase,
//  Confirm and the two pages of "A few things worth knowing" and the closing screen. It stops
//  on the last screen without finishing, so nothing is written.
//

import XCTest

enum OnboardingStep: String, CaseIterable {
    case welcome, restore, storage, localWarning, reveal, confirm, basics, basicsMore, complete
}

/// Launches the app fresh (no `--uitesting`, so onboarding runs) and calls `visit` on each step
/// once it is on screen. The app is left on the closing screen.
@discardableResult
func walkOnboarding(contentSize: String? = nil, file: StaticString = #filePath, line: UInt = #line,
                    visit: (OnboardingStep, XCUIApplication) -> Void) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-appearanceMode", "night"]
    if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
    app.launch()

    let restoreLink = app.buttons["onboarding-restore-link"]
    XCTAssertTrue(restoreLink.waitForExistence(timeout: 12), "onboarding did not appear", file: file, line: line)
    settle()
    visit(.welcome, app)

    let back = app.buttons["Back"]
    tapUntil(restoreLink, appears: back, file: file, line: line)
    settle()
    visit(.restore, app)
    let create = app.buttons["Create my Privacy phrase"]
    tapUntil(back, appears: create, file: file, line: line)
    settle()

    let local = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Local'")).firstMatch
    tapUntil(create, appears: local, file: file, line: line)
    settle()
    visit(.storage, app)

    let risk = app.buttons["I know the risk"]
    tapUntil(local, appears: risk, file: file, line: line)
    settle()
    visit(.localWarning, app)

    let written = app.buttons["I've written them down"]
    tapUntil(risk, appears: written, file: file, line: line)
    settle()
    var words = [String]()
    for position in 1...12 {
        let word = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Word \(position): ")).firstMatch
        if contentSize != nil { scrollUntilHittable(word, in: app) }
        XCTAssertTrue(word.exists, "word \(position) is not on screen", file: file, line: line)
        words.append(word.label.replacingOccurrences(of: "Word \(position): ", with: ""))
    }
    visit(.reveal, app)

    let prompt = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Tap words'")).firstMatch
    tapUntil(written, appears: prompt, file: file, line: line)
    settle()
    visit(.confirm, app)

    let positions = prompt.label.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
    XCTAssertEqual(positions.count, 3, "expected three positions in \"\(prompt.label)\"", file: file, line: line)
    for position in positions where (1...12).contains(position) {
        let tile = app.buttons[words[position - 1]]
        if contentSize != nil { scrollUntilHittable(tile, in: app) }
        tile.tap()
    }
    let next = app.buttons["Next"]
    XCTAssertTrue(next.waitForExistence(timeout: 6), "the first page of points did not appear", file: file, line: line)
    settle()
    visit(.basics, app)

    next.tap()
    let gotIt = app.buttons["Got it"]
    XCTAssertTrue(gotIt.waitForExistence(timeout: 6), "the second page of points did not appear", file: file, line: line)
    settle()
    visit(.basicsMore, app)

    gotIt.tap()
    XCTAssertTrue(app.buttons["Start using Catchlight"].waitForExistence(timeout: 6),
                  "the closing screen did not appear", file: file, line: line)
    settle()
    visit(.complete, app)
    return app
}

/// At the accessibility sizes a step is taller than the screen: swipe the content up until the
/// element can be tapped (not under the pinned buttons).
func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<10 {
        if element.exists && element.isHittable { return }
        app.swipeUp()
    }
}

/// A step crossfades in over 0.18s: let it finish before reading frames.
private func settle() { Thread.sleep(forTimeInterval: 0.6) }
