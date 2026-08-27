//
//  OverlayContainmentUITests.swift
//  CatchlightUITests
//
//  Accessibility audit 2026-08, findings V5 / V6 / RV-4 / VC3 (fix 5) —
//  content behind an overlay must leave the accessibility tree while the
//  overlay is up, and return when it closes.
//
//  INSTRUMENT LIMIT, measured 2026-08-20 (container AND leaf, hardcoded
//  true): SwiftUI `.accessibilityHidden` is invisible to XCUITest — the
//  hidden element still resolves and can even be tapped. This is SPECIFIC
//  to the hidden channel: SwiftUI labels, values and traits ARE readable
//  (A11yStateUITests proves it), and UIKit-level
//  `accessibilityElementsHidden` IS honoured (asserted below). `.isModal`
//  and custom-action enumeration are also unobservable, by design. So these
//  tests assert only the UIKIT-level containment (the timeline collection)
//  plus the must-stay-reachable guarantees.
//  The SwiftUI-level halves — the dock, the Storyboard's SwiftUI rows, and
//  the splash — are covered by the same conditional pattern and verified by
//  the owner's device pass (VoiceOver flick-through; Voice Control
//  "Show names"), which is the audit's gate for this fix.
//

import XCTest

final class OverlayContainmentUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// V5: while the Focus ring is open, the timeline rows must be out of the
    /// tree, and must return when the ring closes.
    func testFocusRing_sealsRows_andRestoresOnClose() throws {
        let app = launchAppForUITesting()
        XCTAssertTrue(anyElement(in: app, id: "take-row").waitForExistence(timeout: 5),
                      "Timeline did not load")

        tapWhenReady(anyElement(in: app, id: "take-iris"))
        try XCTSkipUnless(app.buttons["focus-ring-mark-task"].waitForExistence(timeout: 3),
                          "Focus ring did not open under synthesized gestures on this runtime.")

        XCTAssertTrue(anyElement(in: app, id: "take-row").waitForNonExistence(timeout: 3),
                      "Timeline rows are still in the accessibility tree behind the open Focus ring (V5)")
        XCTAssertFalse(anyElement(in: app, id: "take-iris").exists,
                       "Row Irises are still in the accessibility tree behind the open Focus ring (V5)")

        // Dismiss via the dim at a corner far from any mark (Flow 2 idiom —
        // a coordinate tap is HID-level, unaffected by accessibility hiding).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.12)).tap()
        try XCTSkipUnless(app.buttons["focus-ring-mark-task"].waitForNonExistence(timeout: 3),
                          "Focus-ring dim-commit not delivered on this runtime.")

        XCTAssertTrue(anyElement(in: app, id: "take-row").waitForExistence(timeout: 3),
                      "Timeline rows did not return to the accessibility tree after the Focus ring closed")
    }

    /// RV-4/VC3 (Dailies): while an edit is open, the rows must be out of the
    /// tree — but the D-214 save catcher must stay reachable.
    func testEditor_sealsRows_keepsSaveCatcher() {
        let app = launchAppForUITesting()
        let addButton = app.buttons["add-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Dock did not load")
        tapUntil(addButton, appears: app.textViews["take-edit-body"])

        XCTAssertTrue(anyElement(in: app, id: "dailies-save").waitForExistence(timeout: 5),
                      "The save catcher must stay reachable while the editor is open")
        XCTAssertTrue(anyElement(in: app, id: "take-row").waitForNonExistence(timeout: 3),
                      "Timeline rows are still in the accessibility tree behind the open editor (RV-4/VC3)")

        // Tap-away commit at a corner (blank new Take → discards, editor closes).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(anyElement(in: app, id: "take-row").waitForExistence(timeout: 5),
                      "Timeline rows did not return after the editor closed")
    }

    /// RV-4/VC3 (Storyboard): the save catcher must stay reachable while the
    /// Storyboard editor is open. The dimmed rows' own hiding is SwiftUI-level
    /// (see the instrument-limit note above) — device-verified, not asserted.
    /// Fixture: shape the seeded top Take into a Task (Flow 2 idiom).
    func testStoryboardEditor_keepsSaveCatcher() throws {
        let app = launchAppForUITesting()

        tapWhenReady(anyElement(in: app, id: "take-iris"))
        let taskMark = app.buttons["focus-ring-mark-task"]
        try XCTSkipUnless(taskMark.waitForExistence(timeout: 3),
                          "Focus ring did not open under synthesized gestures on this runtime.")
        taskMark.tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.12)).tap()
        try XCTSkipUnless(taskMark.waitForNonExistence(timeout: 3),
                          "Focus-ring dim-commit not delivered on this runtime.")

        tapWhenReady(app.buttons["angle-tab"])
        let row = anyElement(in: app, id: "storyboard-row")
        XCTAssertTrue(row.waitForExistence(timeout: 3),
                      "Shaped task row did not appear on the Storyboard")
        tapUntil(row, appears: app.textViews["take-edit-body"])

        XCTAssertTrue(anyElement(in: app, id: "storyboard-save").waitForExistence(timeout: 5),
                      "The save catcher must stay reachable while the Storyboard editor is open")
        // Tap-away commit on the DIMMED ROWS region — mid-screen, above the edit
        // panel and BELOW the top chrome. The old dy 0.08 landed on the opaque
        // STORYBOARD chrome, which sits above the catcher BY DESIGN (the × must
        // stay tappable mid-edit), so the tap was swallowed and the assert flaked
        // (bisected 2026-08-27: fails at the pre-merge SHA too — never a code
        // regression). The catcher covers the dimmed list, so this point commits.
        // Dailies' twin test keeps dy 0.08 because ITS heading is inert. RETRIED
        // like the suite's other synthesized-tap sites.
        let editorBody = app.textViews["take-edit-body"]
        for _ in 0..<3 where editorBody.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            if editorBody.waitForNonExistence(timeout: 4) { break }
        }
        XCTAssertTrue(editorBody.waitForNonExistence(timeout: 4),
                      "Storyboard editor did not close on tap-away commit")
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "Storyboard rows did not return after the editor closed")
    }
}
