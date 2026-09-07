//
//  AddButtonFrameProbeTests.swift
//  CatchlightUITests
//
//  V40 probe (audit §15ai), candidate 2: the Add tooltip is `.overlay`'d inside the Button's
//  `label:` closure and positioned with `.offset(y:)`. An offset is a post-layout visual
//  transform, so if the accessibility frame follows LAYOUT rather than render, the button's
//  element inflates to the union of the button and the un-offset bubble — spanning its
//  neighbours, which is both the owner's "focus box around both the tooltip and the two
//  buttons" and a candidate for focus being re-anchored away from an inconsistent frame.
//
//  This measures it rather than asserting the SwiftUI behaviour from memory: the same button,
//  with the tooltip showing (tour step 1) and without it (step 5).
//

import XCTest

final class AddButtonFrameProbeTests: XCTestCase {

    private func addButtonFrame(atStep step: Int) -> CGRect {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", "\(step)"]
        app.launch()
        let add = app.buttons["add-button"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 15), "Dock did not load at step \(step)")
        return add.frame
    }

    func testAddButtonAccessibilityFrameDoesNotInflateWithTheTooltip() {
        let withTip = addButtonFrame(atStep: 1)    // hint 1 showing
        let without = addButtonFrame(atStep: 5)    // tour complete, no tooltip

        // Printed so the numbers are in the log whichever way the assertion goes.
        print("PROBE add-button frame WITH tooltip:    \(withTip)")
        print("PROBE add-button frame WITHOUT tooltip: \(without)")

        XCTAssertEqual(withTip.width, without.width, accuracy: 1.0,
                       "The Add button's accessibility frame WIDENS while the tooltip shows: "
                       + "\(withTip) vs \(without). An offset does not move the accessibility "
                       + "frame, so the element spans its neighbours.")
        XCTAssertEqual(withTip.height, without.height, accuracy: 1.0,
                       "The Add button's accessibility frame GROWS TALLER while the tooltip "
                       + "shows: \(withTip) vs \(without).")
    }
}
