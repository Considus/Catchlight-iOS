//
//  BlockEditorReorderGeometryTests.swift
//  CatchlightCoreTests — the UIKit editor's checklist-reorder maths
//
//  Replaces `InlineReorderGeometryTests`, which tested the RETIRED SwiftUI editor's
//  `rowCenters`/`reorderTarget` statics and was deleted with it at M7 (PR #130) — leaving reorder
//  with no coverage at all. The UIKit editor makes the same decision by REAL row centres (so a drag
//  over wrapped multi-line rows lands where the finger is; a fixed row height under/overshot tall
//  rows — owner 2026-06-21), just from live view frames rather than measured heights. The pure part
//  is `BlockEditorViewController.reorderTarget`; the drag mechanics are on-device (the simulator
//  doesn't deliver synthesized drags reliably — see `BlockEditorUITests.testReorder_dragHandle`).
//
//  App-target only, matching the file it replaces.
//

#if canImport(Catchlight)
import XCTest
import CoreGraphics
@testable import Catchlight

final class BlockEditorReorderGeometryTests: XCTestCase {

    /// Rows of equal height 44 + 2 spacing → centres at 22, 68, 114, 160.
    private let evenRows: [CGFloat] = [22, 68, 114, 160]

    // MARK: - Resting

    func testTarget_draggedAboveEveryRow_isFirstSlot() {
        XCTAssertEqual(BlockEditorViewController.reorderTarget(draggedCenterY: 0,
                                                              otherCenterYs: evenRows), 0)
    }

    func testTarget_draggedBelowEveryRow_clampsToLastSlot() {
        XCTAssertEqual(BlockEditorViewController.reorderTarget(draggedCenterY: 1000,
                                                              otherCenterYs: evenRows), 4)
    }

    // MARK: - Stepping through slots

    func testTarget_stepsSlotAsTheDragPassesEachCentre() {
        // Just past the first centre → slot 1; past the second → slot 2; and so on.
        XCTAssertEqual(BlockEditorViewController.reorderTarget(draggedCenterY: 23,
                                                              otherCenterYs: evenRows), 1)
        XCTAssertEqual(BlockEditorViewController.reorderTarget(draggedCenterY: 69,
                                                              otherCenterYs: evenRows), 2)
        XCTAssertEqual(BlockEditorViewController.reorderTarget(draggedCenterY: 115,
                                                              otherCenterYs: evenRows), 3)
    }

    func testTarget_exactlyOnACentre_doesNotYetPassIt() {
        // Strictly-less-than: sitting exactly on a centre leaves the row above it, so a
        // resting row can't jitter between two slots.
        XCTAssertEqual(BlockEditorViewController.reorderTarget(draggedCenterY: 68,
                                                              otherCenterYs: evenRows), 1)
    }

    // MARK: - No-op: released in the origin slot

    func testTarget_releasedInOriginSlot_leavesOrderUnchanged() {
        // Lift the row at index 2 and let go without moving it. `otherCenterYs` is every OTHER
        // row (the dragged one is excluded), so the two rows originally above it stay above and
        // the target comes back as 2 — the same slot, i.e. no reorder. This is the common case:
        // a stray touch on the drag handle must not shuffle the list.
        let others: [CGFloat] = [22, 68, 160, 206]   // rows 0,1,3,4 — index 2 (centre 114) is dragged
        XCTAssertEqual(BlockEditorViewController.reorderTarget(draggedCenterY: 114,
                                                              otherCenterYs: others), 2)
    }

    // MARK: - The reason this maths exists: TALL rows

    func testTarget_tallWrappedRow_usesItsRealCentreNotAFixedHeight() {
        // A wrapped multi-line row: heights 44 / 120 / 44 → centres 22, 106, 188.
        // Dragging to y=100 is still ABOVE the tall row's real centre (106), so the finger
        // has not passed it — slot 1. A fixed 44pt row height would have called this slot 2
        // and overshot, which is the bug this replaced (owner 2026-06-21).
        let tall: [CGFloat] = [22, 106, 188]
        XCTAssertEqual(BlockEditorViewController.reorderTarget(draggedCenterY: 100,
                                                              otherCenterYs: tall), 1)
        // Past the tall row's centre → slot 2.
        XCTAssertEqual(BlockEditorViewController.reorderTarget(draggedCenterY: 110,
                                                              otherCenterYs: tall), 2)
    }

    // MARK: - Degenerate inputs

    func testTarget_noOtherRows_isAlwaysSlotZero() {
        XCTAssertEqual(BlockEditorViewController.reorderTarget(draggedCenterY: 50,
                                                              otherCenterYs: []), 0)
    }

    func testTarget_singleOtherRow_bothSides() {
        XCTAssertEqual(BlockEditorViewController.reorderTarget(draggedCenterY: 10,
                                                              otherCenterYs: [22]), 0)
        XCTAssertEqual(BlockEditorViewController.reorderTarget(draggedCenterY: 30,
                                                              otherCenterYs: [22]), 1)
    }

    /// `prefix(while:)`, not `filter(_:).count` — it stops at the FIRST row below the drag.
    /// The two agree only while centres ascend, which they do for a real stack. Pinned here so
    /// nobody "simplifies" it into a filter-count and silently changes behaviour on odd input.
    func testTarget_stopsAtTheFirstRowBelow_ratherThanCountingAllRowsAbove() {
        // Deliberately unsorted: 22 is above the drag, 300 is below, 40 is above again.
        // prefix-while stops at 300 → 1. A filter-count would say 2.
        XCTAssertEqual(BlockEditorViewController.reorderTarget(draggedCenterY: 50,
                                                              otherCenterYs: [22, 300, 40]), 1)
    }
}
#endif
