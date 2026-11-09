//
//  FocusRowLayoutTests.swift
//  CatchlightTests (app module)
//
//  Covers where the Focus row's four marks land: 52pt apart to the right of the
//  Iris on a standard phone, and squeezed evenly (never shrunk) when the row
//  would otherwise run past the screen's 8pt margin.
//

import XCTest
@testable import Catchlight

final class FocusRowLayoutTests: XCTestCase {

    private func slots(hubX: CGFloat, width: CGFloat) -> [CGFloat] {
        (0..<4).map { FocusRowView.slotX(for: $0, hubX: hubX, containerWidth: width) }
    }

    /// 393pt wide with the Iris at the real card position: four marks at 52, 104, 156, 208.
    func testStandardWidth_marksSit52Apart() {
        let hubX = CatchlightLayout.spineX(containerWidth: 393)
        XCTAssertEqual(slots(hubX: hubX, width: 393), [52, 104, 156, 208])
    }

    /// The narrowest supported phone keeps the last mark at least 8pt inside the screen,
    /// with equal gaps.
    func testNarrowestPhone_lastMarkStaysInsideTheMargin() {
        let width: CGFloat = 375
        let hubX = CatchlightLayout.spineX(containerWidth: width)
        let xs = slots(hubX: hubX, width: width)
        XCTAssertLessThanOrEqual(hubX + xs[3] + FocusRowView.markSize / 2, width - 8)
        assertEqualGaps(xs)
    }

    /// When the Iris sits far enough right that the standard row would overflow, the gap
    /// shrinks evenly so the last mark's right edge lands exactly on the 8pt margin.
    func testOverflow_gapShrinksEvenlyToTheMargin() {
        let width: CGFloat = 375
        let hubX: CGFloat = 200
        let xs = slots(hubX: hubX, width: width)
        XCTAssertEqual(hubX + xs[3] + FocusRowView.markSize / 2, width - 8, accuracy: 0.0001)
        XCTAssertLessThan(xs[0], 52)
        assertEqualGaps(xs)
    }

    /// The mark is never resized to fit: it stays a 44pt touch target.
    func testMarkSizeNeverDropsBelow44() {
        XCTAssertGreaterThanOrEqual(FocusRowView.markSize, 44)
        XCTAssertGreaterThanOrEqual(FocusRowView.markSize, CatchlightLayout.minTouchTarget)
    }

    /// The row sits centred on the card's top edge: the Iris centre is 36 below it.
    func testRowSitsOnTheCardTopEdge() {
        XCTAssertEqual(FocusRowView.irisCentreInset, 36)
    }

    private func assertEqualGaps(_ xs: [CGFloat], file: StaticString = #filePath, line: UInt = #line) {
        let gap = xs[0]
        for i in 1..<xs.count {
            XCTAssertEqual(xs[i] - xs[i - 1], gap, accuracy: 0.0001, file: file, line: line)
        }
    }
}
