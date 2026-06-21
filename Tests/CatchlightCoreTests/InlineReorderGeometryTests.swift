//
//  InlineReorderGeometryTests.swift
//  CatchlightCoreTests — measured-height reorder maths (owner 2026-06-21)
//
//  The inline editor's checklist reorder maps finger travel to a target row by REAL row
//  centres, so a drag over wrapped multi-line rows lands where the finger is (the old
//  fixed 44pt row height under/overshot tall rows). The pure geometry is tested here;
//  the on-device drag feel is verified separately. App-target only.
//

#if canImport(Catchlight)
import XCTest
import CoreGraphics
@testable import Catchlight

final class InlineReorderGeometryTests: XCTestCase {

    func testRowCenters_uniformRows() {
        let centers = InlineTakeEditCard.rowCenters(heights: [44, 44, 44], spacing: 2)
        XCTAssertEqual(centers, [22, 68, 114])   // 22 ; 44+2+22 ; 88+4+22
    }

    func testRowCenters_variableRows() {
        let centers = InlineTakeEditCard.rowCenters(heights: [44, 120, 44], spacing: 2)
        XCTAssertEqual(centers, [22, 106, 190])  // 22 ; 44+2+60 ; 44+2+120+2+22
    }

    func testReorderTarget_uniform_stepsByRow() {
        let centers = InlineTakeEditCard.rowCenters(heights: [44, 44, 44, 44], spacing: 2)
        XCTAssertEqual(InlineTakeEditCard.reorderTarget(centers: centers, start: 0, translationY: 0), 0)
        XCTAssertEqual(InlineTakeEditCard.reorderTarget(centers: centers, start: 0, translationY: 46), 1)   // one row down
        XCTAssertEqual(InlineTakeEditCard.reorderTarget(centers: centers, start: 0, translationY: 1000), 3) // clamps to last
        XCTAssertEqual(InlineTakeEditCard.reorderTarget(centers: centers, start: 3, translationY: -92), 1)  // two rows up
    }

    /// The bug case: dragging the first item DOWN over a tall, wrapped middle row. With a
    /// fixed 44pt height, round(100/44) = 2 overshoots past the middle; with real centres
    /// the finger at 122 is nearest the middle row's centre (106) → index 1.
    func testReorderTarget_wrappedRow_doesNotOvershoot() {
        let centers = InlineTakeEditCard.rowCenters(heights: [44, 120, 44], spacing: 2)
        XCTAssertEqual(InlineTakeEditCard.reorderTarget(centers: centers, start: 0, translationY: 100), 1)
        // Only once the finger reaches the far row's centre (190) does it select index 2.
        XCTAssertEqual(InlineTakeEditCard.reorderTarget(centers: centers, start: 0, translationY: 168), 2)
    }

    func testReorderTarget_emptyOrOutOfRange_returnsStart() {
        XCTAssertEqual(InlineTakeEditCard.reorderTarget(centers: [], start: 0, translationY: 50), 0)
        XCTAssertEqual(InlineTakeEditCard.reorderTarget(centers: [22, 68], start: 5, translationY: 0), 5)
    }
}
#endif
