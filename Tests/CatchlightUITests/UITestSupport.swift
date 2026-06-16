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

// MARK: - Race-hardening interaction helpers
//
// Every synthesized interaction below FIRST waits for the element to exist,
// failing with a precise message if it never appears. This closes the
// simulator timing race the suite documents: a bare `.tap()` / `.typeText()` /
// `.swipeUp()` fires a beat before the element resolves from the accessibility
// query, surfacing as "element did not appear" / "No matches found" /
// "Failed to scroll to visible (kAXErrorCannotComplete)" even though the
// element IS in the tree at failure time. Route no-wait interactions through
// these; prefer querying by a stable accessibilityIdentifier over a label so
// they stay robust to copy changes. The default 5s is deliberately generous
// for loaded CI simulators.

/// Resolve an element by its accessibilityIdentifier regardless of element TYPE.
/// A SwiftUI `.accessibilityElement()` wrapper (e.g. the editor footer Iris,
/// "editor-shape") surfaces as `.other` on some runtimes and `.button` on
/// others, so a type-pinned query like `app.buttons["editor-shape"]` matches on
/// one iOS version and silently misses on the next (verified: on iOS 18.6 the
/// footer Iris is an `Other`, so `.buttons` never resolves it). Matching `.any`
/// by identifier is stable across runtimes — prefer it for elements whose
/// trait/type isn't guaranteed.
func anyElement(in app: XCUIApplication, id: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: id).firstMatch
}

/// Wait for `element` to exist (default 5s), then tap it. Returns the element.
@discardableResult
func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 5,
                  file: StaticString = #file, line: UInt = #line) -> XCUIElement {
    XCTAssertTrue(element.waitForExistence(timeout: timeout),
                  "tapWhenReady: element did not appear within \(timeout)s",
                  file: file, line: line)
    element.tap()
    return element
}

/// Tap `target` and wait for `result` to appear; if it doesn't, re-tap (up to
/// `attempts`). A synthesized tap on a present element is occasionally swallowed
/// before the view's gesture recognizer is armed — surfacing as the editor /
/// sheet simply never opening even though the tapped element was in the tree.
/// Re-issuing the SAME tap compensates without masking a real bug: if `result`
/// never appears after `attempts` taps the test still fails. Use for idempotent
/// open/navigate taps (opening the editor, a sheet) — NOT for toggles, where a
/// second tap would undo the first.
@discardableResult
func tapUntil(_ target: XCUIElement, appears result: XCUIElement,
              attempts: Int = 3, timeout: TimeInterval = 5,
              file: StaticString = #file, line: UInt = #line) -> Bool {
    XCTAssertTrue(target.waitForExistence(timeout: timeout),
                  "tapUntil: target element did not appear within \(timeout)s",
                  file: file, line: line)
    for _ in 0..<attempts {
        target.tap()
        if result.waitForExistence(timeout: timeout) { return true }
    }
    XCTFail("tapUntil: result element did not appear after \(attempts) taps",
            file: file, line: line)
    return false
}

/// Wait for `element`, then type into it. (For an already-focused responder
/// where an AX scroll-to-visible would itself flake, prefer `app.typeText`.)
func typeWhenReady(_ element: XCUIElement, _ text: String, timeout: TimeInterval = 5,
                   file: StaticString = #file, line: UInt = #line) {
    XCTAssertTrue(element.waitForExistence(timeout: timeout),
                  "typeWhenReady: element did not appear within \(timeout)s",
                  file: file, line: line)
    element.typeText(text)
}

/// Wait for `element`, then swipe up on it (the Settings dock gesture).
func swipeUpWhenReady(_ element: XCUIElement, timeout: TimeInterval = 5,
                      file: StaticString = #file, line: UInt = #line) {
    XCTAssertTrue(element.waitForExistence(timeout: timeout),
                  "swipeUpWhenReady: element did not appear within \(timeout)s",
                  file: file, line: line)
    element.swipeUp()
}

/// Wait for `element`, then long-press it for `duration`.
func pressWhenReady(_ element: XCUIElement, forDuration duration: TimeInterval,
                    timeout: TimeInterval = 5,
                    file: StaticString = #file, line: UInt = #line) {
    XCTAssertTrue(element.waitForExistence(timeout: timeout),
                  "pressWhenReady: element did not appear within \(timeout)s",
                  file: file, line: line)
    element.press(forDuration: duration)
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
    // Re-issue the SINGLE interaction if a synthesized event is dropped (the
    // simulator intermittently swallows a synthesized tap/swipe before the
    // view's recognizer is armed, so the destination never opens even though the
    // tapped element was present). This does NOT relax the two-tap rule: the
    // same one interaction is re-issued, and re-issuing only happens when the
    // expected element is ABSENT (i.e. the navigation has not occurred), so a
    // flow that genuinely needs a second, DIFFERENT interaction still cannot
    // satisfy the assertion. 5s per attempt (was a single 2s wait) also absorbs
    // post-interaction render lag under CI load.
    for _ in 0..<3 {
        firstInteraction()
        if expectedElement.waitForExistence(timeout: 5) { return }
    }
    XCTFail(
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
    // Re-issue the single interaction on a dropped synthesized event — see
    // assertReachableInTwoInteractions for why this preserves the rule.
    for _ in 0..<3 {
        interaction()
        if expectedElement.waitForExistence(timeout: 5) { return }
    }
    XCTFail(
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
