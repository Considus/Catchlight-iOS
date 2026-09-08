//
//  DockOrderProbeTests.swift
//  CatchlightUITests
//
//  V40, third characterisation (audit §15ak). The owner's third export shows that
//  nothing is stealing focus at all: EVERY forward move out of a dock element lands
//  on the first timeline cell. Eight transitions, one destination. From `Search`
//  that is a legitimate wrap off the end of the dock; from Add, Storyboard,
//  Sequence and the hint it is not.
//
//  So each dock element is behaving as though it were the LAST element on the
//  screen, and only while the Add hint is mounted. That is a traversal-ORDER fault,
//  not a focus event — and order, unlike focus movement, IS observable on the
//  simulator. The earlier conclusion that nothing about V40 could be measured on
//  the bench applied to the cursor, and was carried too far.
//
//  This dumps the ordered accessibility tree with the hint mounted (tour step 1)
//  and without it (step 5, complete), and asserts the four dock buttons stay one
//  contiguous run in both. No production code is involved in setting the
//  condition: `--uitesting-orientation-step` already selects it.
//

import XCTest

final class DockOrderProbeTests: XCTestCase {

    /// Identifiers of the four resting-dock buttons, in the order they are laid out.
    private static let dockIDs = ["add-button", "angle-tab", "sequence-tab", "search-tab"]

    private func orderedTree(step: String) -> [(id: String, label: String, type: String, frame: CGRect)] {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", step]
        app.launch()
        XCTAssertTrue(app.buttons["add-button"].firstMatch.waitForExistence(timeout: 20),
                      "Dock did not load at step \(step)")

        return app.descendants(matching: .any).allElementsBoundByIndex.compactMap { el in
            guard el.exists else { return nil }
            let id = el.identifier
            let label = el.label
            guard !id.isEmpty || !label.isEmpty else { return nil }
            return (id, label, String(describing: el.elementType), el.frame)
        }
    }

    private func report(_ tree: [(id: String, label: String, type: String, frame: CGRect)], _ title: String) -> [Int] {
        print("=== \(title): \(tree.count) elements ===")
        for (i, e) in tree.enumerated() {
            let mark = Self.dockIDs.contains(e.id) ? " <== DOCK" : ""
            print(String(format: "%3d  type=%@ frame=%@ id=%@  label=%@%@",
                         i, e.type, NSCoder.string(for: e.frame), e.id, e.label, mark))
        }
        let positions = tree.enumerated().compactMap { Self.dockIDs.contains($0.element.id) ? $0.offset : nil }
        print("=== \(title) dock positions: \(positions) ===")
        return positions
    }

    func testDockStaysOneContiguousRunWhetherOrNotTheAddHintIsMounted() {
        let withHint = orderedTree(step: "1")
        let hintPresent = withHint.contains { $0.label.contains("first Take") }
        let withHintPositions = report(withHint, "STEP 1 (Add hint mounted)")
        XCTAssertTrue(hintPresent,
                      "Step 1 did not mount the Add hint, so this measures nothing.")

        // The tooltip must be ONE stop, not two. Measured 2026-09-08: the bare
        // `.accessibilityElement()` left the inner Text vending alongside the
        // container it created, so the hint appeared twice with identical words —
        // an `.other` at (12, 713.7) 173x46.3 and a `.staticText` at (26, 723.7)
        // 145x18.3. Two adjacent stops saying the same sentence is the "cannot get
        // past the tooltip" trap from the inside.
        let hintNodes = withHint.filter { $0.label.contains("first Take") }
        XCTAssertEqual(hintNodes.count, 1,
                       "The Add hint vends \(hintNodes.count) accessibility elements, not 1: "
                       + hintNodes.map { "\($0.type) \($0.frame)" }.joined(separator: " | "))

        let noHint = orderedTree(step: "5")
        let noHintPositions = report(noHint, "STEP 5 (tour complete, no hint)")
        XCTAssertFalse(noHint.contains { $0.label.contains("first Take") },
                       "Step 5 still shows the Add hint; the control condition is not clean.")

        XCTAssertEqual(noHintPositions.count, Self.dockIDs.count,
                       "Control: not all four dock buttons vend. Got \(noHintPositions)")
        XCTAssertEqual(withHintPositions.count, Self.dockIDs.count,
                       "With the hint: not all four dock buttons vend. Got \(withHintPositions)")

        // The load-bearing comparison. Contiguous means each button is followed by the
        // next with nothing between them — one run VoiceOver can swipe along. If the
        // hint splits the run, the gaps appear here.
        func gaps(_ p: [Int]) -> [Int] { zip(p, p.dropFirst()).map { $1 - $0 } }
        let controlGaps = gaps(noHintPositions)
        let hintGaps = gaps(withHintPositions)
        print("=== control gaps \(controlGaps) vs with-hint gaps \(hintGaps) ===")

        XCTAssertEqual(hintGaps, controlGaps,
                       "The dock's traversal order CHANGES when the Add hint is mounted: "
                       + "gaps \(hintGaps) with the hint against \(controlGaps) without. "
                       + "Positions \(withHintPositions) vs \(noHintPositions). That is V40.")
    }
}
