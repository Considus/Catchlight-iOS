//
//  FocusRowLayoutTests.swift
//  CatchlightTests (app module)
//
//  Covers where the Focus row's four marks land: 52pt apart to the right of the
//  Iris on a standard phone, squeezed evenly (never shrunk) when the row would
//  otherwise run past the screen's 8pt margin, and 8pt below the card's bottom
//  edge, lifted to stay above the keyboard or the dock.
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

    /// The Iris centre is 36 in from the card's top and leading edges.
    func testHubCentre_is36InFromTheCardsTopLeft() {
        let card = CGRect(x: 20, y: 200, width: 353, height: 72)
        XCTAssertEqual(FocusRowView.hubCentre(of: card), CGPoint(x: 56, y: 236))
    }

    /// The card frame a host reports is rebuilt from the Iris centre and the card's size.
    func testCardFrame_fromIrisCentreAndSize() {
        XCTAssertEqual(FocusRowView.cardFrame(irisCentre: CGPoint(x: 56, y: 236),
                                              cardSize: CGSize(width: 353, height: 140)),
                       CGRect(x: 20, y: 200, width: 353, height: 140))
    }

    /// A 72pt card: its bottom edge is 72 - 36 = 36 below the Iris centre, and the row's
    /// centre sits 8 below that, 44 below the Iris centre.
    func testRowY_shortCard_sits8BelowTheBottomEdge() {
        let card = CGRect(x: 20, y: 200, width: 353, height: 72)
        XCTAssertEqual(FocusRowView.rowY(cardFrame: card, visibleBottom: 852), 44)
    }

    /// A 140pt card: bottom edge 140 - 36 = 104 below the Iris centre, the row 112.
    func testRowY_tallCard_sits8BelowTheBottomEdge() {
        let card = CGRect(x: 20, y: 200, width: 353, height: 140)
        XCTAssertEqual(FocusRowView.rowY(cardFrame: card, visibleBottom: 852), 112)
    }

    /// With the marks 44 tall, an 8pt drop puts their top edge on the card's 14pt bottom
    /// padding line, clear of the last line of text.
    func testRowY_marksTopSitsOnTheCardsBottomPaddingLine() {
        XCTAssertEqual(FocusRowView.belowEdge, 8)
        XCTAssertEqual(FocusRowView.belowEdge - FocusRowView.markSize / 2, -CatchlightLayout.cardPadding)
    }

    /// A card whose bottom edge runs past the visible area: Iris centre at 636, row centre
    /// would be 636 + 112 = 748, but the lowest a 44pt mark can sit with the visible area
    /// ending at 700 is 678, so the row lifts to 42 below the Iris centre.
    func testRowY_clampsAboveTheVisibleBottom() {
        let card = CGRect(x: 20, y: 600, width: 353, height: 140)
        XCTAssertEqual(FocusRowView.rowY(cardFrame: card, visibleBottom: 700), 42)
    }

    /// The clamp never lifts the row above the Iris itself.
    func testRowY_clampNeverRisesAboveTheIris() {
        let card = CGRect(x: 20, y: 680, width: 353, height: 140)
        XCTAssertEqual(FocusRowView.rowY(cardFrame: card, visibleBottom: 700), 0)
    }

    private func assertEqualGaps(_ xs: [CGFloat], file: StaticString = #filePath, line: UInt = #line) {
        let gap = xs[0]
        for i in 1..<xs.count {
            XCTAssertEqual(xs[i] - xs[i - 1], gap, accuracy: 0.0001, file: file, line: line)
        }
    }
}
