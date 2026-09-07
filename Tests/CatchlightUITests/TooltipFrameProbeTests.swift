//
//  TooltipFrameProbeTests.swift
//  CatchlightUITests
//
//  V40 (audit §15aj). The owner's capture eliminates the two mechanisms we had: no
//  accessibility post precedes a steal, and the only timeline reload is three minutes before
//  one. What remains is that the steal is conditional on the tooltip being MOUNTED — 13 dock
//  arrivals with no tooltip produced 0 steals; 3 arrivals with it produced 2.
//
//  #235 moved the hint out of the Add Button and onto the dock row, which fixed the BUTTON's
//  frame (measured 348x180 -> 44x44). But the tooltip is still positioned with `.offset(y:)`,
//  and an offset is a post-layout visual transform. So the tooltip's OWN accessibility frame
//  should still sit at its un-offset origin — on top of the dock buttons it renders above.
//
//  If that holds, VoiceOver has an element whose frame overlaps the dock's controls while its
//  pixels are elsewhere, which is a candidate for re-anchoring when focus lands on a button
//  underneath it. This measures the frame rather than assuming the behaviour.
//

import XCTest

final class TooltipFrameProbeTests: XCTestCase {

    func testAddHintFrameSitsWhereItIsDrawn() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", "1"]
        app.launch()

        let add = app.buttons["add-button"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 15), "Dock did not load")

        let hint = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'first Take'")).firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 10), "The Add hint is not an element at all")

        print("PROBE add-button frame: \(add.frame)")
        print("PROBE add-hint    frame: \(hint.frame)")

        // The hint is DRAWN above the dock. If its accessibility frame instead overlaps the
        // dock buttons, the offset has not moved it and VoiceOver sees them on top of another.
        XCTAssertFalse(hint.frame.intersects(add.frame),
                       "The Add hint's accessibility frame OVERLAPS the Add button's: "
                       + "hint \(hint.frame) vs button \(add.frame). It is drawn above the "
                       + "dock, so an overlap means .offset moved the pixels and not the frame.")
        XCTAssertLessThan(hint.frame.maxY, add.frame.minY + 1,
                          "The hint's frame should sit ABOVE the Add button, as it is drawn: "
                          + "hint \(hint.frame) vs button \(add.frame)")
    }
}
