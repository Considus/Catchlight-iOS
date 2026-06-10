//
//  UITestSupport.swift
//  CatchlightUITests
//
//  Shared XCUITest scaffolding — app launch with the --uitesting flag and the
//  two-tap reachability assertion used by every flow in CoreFlowsUITests and
//  the standalone regression in TwoTapRegressionTests.
//

import XCTest

/// Launch the app with a clean, predictable state for UI testing. The flag
/// `--uitesting` is consumed by `Wiring.makeAppModel`, which short-circuits
/// onboarding and seeds an `InMemoryTakeStore` with two known Takes:
///   • "Buy film for the weekend shoot"
///   • "Call the framer back"
/// Every test method calls this in setUp so methods are independent — no shared
/// mutable state across tests.
@discardableResult
func launchAppForUITesting() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitesting"]
    app.launch()
    return app
}

/// Two-tap rule helper — the primary structural invariant of Catchlight's UI
/// (Product Brief principle: every primary action reachable within two
/// interactions from Dailies). Each call to `firstInteraction` MUST be one tap,
/// one swipe, or one long-press; chaining multiple inside the closure violates
/// the rule the helper is meant to enforce.
func assertReachableInTwoInteractions(
    _ name: String,
    firstInteraction: () -> Void,
    expectedElement: XCUIElement,
    file: StaticString = #file,
    line: UInt = #line
) {
    firstInteraction()
    XCTAssertTrue(
        expectedElement.waitForExistence(timeout: 2),
        "\(name): expected element did not appear within two interactions",
        file: file, line: line
    )
}

/// Convenience for one-interaction reachability (the regression anchor in
/// `TwoTapRegressionTests`). Same contract — exactly one tap / swipe / press.
func assertReachableInOneInteraction(
    _ name: String,
    interaction: () -> Void,
    expectedElement: XCUIElement,
    file: StaticString = #file,
    line: UInt = #line
) {
    interaction()
    XCTAssertTrue(
        expectedElement.waitForExistence(timeout: 2),
        "\(name): expected element did not appear within one interaction",
        file: file, line: line
    )
}

/// Find a Take row whose composed accessibility label begins with the given
/// prefix. Because TakeRowView combines its children into a single VO element
/// (so the row reads as one sentence: "Buy milk. Note."), the body text is no
/// longer queryable as a bare `app.staticTexts[…]` match — it lives on the
/// `take-row` composite element's label.
func takeRow(in app: XCUIApplication, withLabelStarting prefix: String) -> XCUIElement {
    let predicate = NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@",
                                "take-row", prefix)
    return app.descendants(matching: .any).matching(predicate).firstMatch
}
