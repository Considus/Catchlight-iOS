//
//  FocusRowLayoutTests.swift
//  CatchlightTests (app module)
//
//  Covers where the Focus row's four marks land: 44pt marks with 16pt gaps, centres
//  60, 120, 180 and 240pt right of the Iris on a phone, squeezed evenly (never shrunk,
//  never overlapping) when the row would otherwise run past the screen's 8pt margin.
//  The tapped card grows 22pt at the bottom while the row is open, and the marks'
//  centres sit exactly on its grown bottom edge, lifted to stay above the keyboard or
//  the dock.
//

import XCTest
@testable import Catchlight

final class FocusRowLayoutTests: XCTestCase {

    private func slots(hubX: CGFloat, width: CGFloat) -> [CGFloat] {
        (0..<4).map { FocusRowView.slotX(for: $0, hubX: hubX, containerWidth: width) }
    }

    /// 44pt marks with 16pt gaps between them.
    func testMarksAre44WithA16Gap() {
        XCTAssertEqual(FocusRowView.markSize, 44)
        XCTAssertEqual(FocusRowView.markSpacing - FocusRowView.markSize, 16)
    }

    /// 393pt wide with the Iris at the real card position: four marks at 60, 120, 180, 240.
    func testStandardWidth_marksSit60Apart() {
        let hubX = CatchlightLayout.spineX(containerWidth: 393)
        XCTAssertEqual(slots(hubX: hubX, width: 393), [60, 120, 180, 240])
    }

    /// The narrowest supported phone (375) has room for the full spacing.
    func testNarrowestPhone_keepsTheFullSpacing() {
        let width: CGFloat = 375
        let hubX = CatchlightLayout.spineX(containerWidth: width)
        let xs = slots(hubX: hubX, width: width)
        XCTAssertEqual(xs, [60, 120, 180, 240])
        XCTAssertLessThanOrEqual(hubX + xs[3] + FocusRowView.markSize / 2, width - 8)
    }

    /// The squeeze starts below 318.9pt wide with the Iris at the real card position: at
    /// 320 the last mark's edge (49 + 240 + 22 = 311) is inside the margin (312); at 318
    /// it is not (48.75 + 262 = 310.75 > 310), so the gap shrinks.
    func testSqueezeThreshold() {
        XCTAssertEqual(slots(hubX: CatchlightLayout.spineX(containerWidth: 320), width: 320),
                       [60, 120, 180, 240])
        let xs = slots(hubX: CatchlightLayout.spineX(containerWidth: 318), width: 318)
        XCTAssertLessThan(xs[0], 60)
        assertEqualGaps(xs)
    }

    /// When the Iris sits far enough right that the standard row would overflow, the gap
    /// shrinks evenly so the last mark's right edge lands exactly on the 8pt margin.
    func testOverflow_gapShrinksEvenlyToTheMargin() {
        let width: CGFloat = 375
        let hubX: CGFloat = 160
        let xs = slots(hubX: hubX, width: width)
        XCTAssertEqual(hubX + xs[3] + FocusRowView.markSize / 2, width - 8, accuracy: 0.0001)
        XCTAssertLessThan(xs[0], 60)
        assertEqualGaps(xs)
    }

    /// However little room there is, the marks never overlap: 44pt apart at the least.
    func testSqueeze_neverOverlaps() {
        XCTAssertEqual(slots(hubX: 200, width: 300), [44, 88, 132, 176])
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

    /// The open row grows the tapped card by half a mark at the bottom, so the marks,
    /// centred on its edge, clear the last line of text.
    func testCardGrowth_isHalfAMark() {
        XCTAssertEqual(FocusRowView.cardGrowth, 22)
    }

    /// A 72pt card grows to 94: its grown bottom edge is 94 - 36 = 58 below the Iris centre,
    /// and the marks' centres sit exactly on it.
    func testRowY_shortCard_sitsOnTheGrownBottomEdge() {
        let card = CGRect(x: 20, y: 200, width: 353, height: 72)
        XCTAssertEqual(FocusRowView.rowY(cardFrame: card, visibleBottom: 852), 58)
        XCTAssertEqual(FocusRowView.hubCentre(of: card).y + 58, card.maxY + 22)
    }

    /// A 140pt card grows to 162: the marks' centres 162 - 36 = 126 below the Iris centre.
    func testRowY_tallCard_sitsOnTheGrownBottomEdge() {
        let card = CGRect(x: 20, y: 200, width: 353, height: 140)
        XCTAssertEqual(FocusRowView.rowY(cardFrame: card, visibleBottom: 852), 126)
        XCTAssertEqual(FocusRowView.hubCentre(of: card).y + 126, card.maxY + 22)
    }

    /// A card whose grown bottom edge runs past the visible area: Iris centre at 636, row
    /// centre would be 636 + 126 = 762, but the lowest a 44pt mark can sit with the visible
    /// area ending at 700 is 678, so the row lifts to 42 below the Iris centre.
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
