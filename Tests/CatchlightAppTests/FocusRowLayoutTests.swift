//
//  FocusRowLayoutTests.swift
//  CatchlightTests (app module)
//
//  Covers where the Focus row's four marks land: 44pt marks with 16pt gaps, as a group
//  centred on the screen (and so the card), squeezed evenly (never shrunk, never
//  overlapping) only on a screen too narrow for the full row and an 8pt margin each side.
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

    /// The four marks sit as one group centred on the screen, which is the card's centre, at
    /// every phone width (owner 2026-11-12: they sat 12pt right of centre on a 402pt phone).
    func testTheGroupIsCentred_atEveryPhoneWidth() {
        for width: CGFloat in [375, 393, 402, 440] {
            let hubX = CatchlightLayout.addColumnX(containerWidth: width)
            let xs = slots(hubX: hubX, width: width)
            let groupMid = hubX + (xs[0] + xs[3]) / 2
            XCTAssertEqual(groupMid, width / 2, accuracy: 0.0001, "Off centre at \(width)pt")
            assertEqualGaps(xs)
            XCTAssertEqual(xs[1] - xs[0], 60, accuracy: 0.0001, "Spacing changed at \(width)pt")
        }
    }

    /// On a 402pt phone the Iris is at 63, so the marks' centres are 111, 171, 231 and 291.
    func testStandardPhone_marksSit60Apart_aroundTheCentre() {
        XCTAssertEqual(slots(hubX: 63, width: 402), [48, 108, 168, 228])
    }

    /// Every mark is still right of the Iris on every phone, so each one slides right.
    func testEveryMarkSlidesRight() {
        for width: CGFloat in [375, 393, 402, 440] {
            let hubX = CatchlightLayout.addColumnX(containerWidth: width)
            XCTAssertGreaterThan(slots(hubX: hubX, width: width)[0], 0, "Note is left of the Iris at \(width)pt")
        }
    }

    /// Only a screen narrower than the full row plus 8pt each side (240pt) shrinks the gap,
    /// evenly, keeping the group centred and inside the margins.
    func testSqueeze_belowTheFullRow() {
        XCTAssertEqual(slots(hubX: 30, width: 240), [0, 60, 120, 180])
        let xs = slots(hubX: 30, width: 220)
        XCTAssertLessThan(xs[1] - xs[0], 60)
        assertEqualGaps(xs)
        XCTAssertEqual(30 + xs[0] - FocusRowView.markSize / 2, 8, accuracy: 0.0001)
        XCTAssertEqual(30 + xs[3] + FocusRowView.markSize / 2, 220 - 8, accuracy: 0.0001)
    }

    /// However little room there is, the marks never overlap: 44pt apart at the least.
    func testSqueeze_neverOverlaps() {
        let xs = slots(hubX: 20, width: 100)
        XCTAssertEqual(xs[1] - xs[0], 44, accuracy: 0.0001)
        assertEqualGaps(xs)
    }

    /// Before the container has a width, the marks sit a full spacing apart from the Iris.
    func testNoWidthYet_marksSit60ApartFromTheIris() {
        XCTAssertEqual(slots(hubX: 63, width: 0), [60, 120, 180, 240])
    }

    /// The mark is never resized to fit: it stays a 44pt touch target.
    func testMarkSizeNeverDropsBelow44() {
        XCTAssertGreaterThanOrEqual(FocusRowView.markSize, 44)
        XCTAssertGreaterThanOrEqual(FocusRowView.markSize, CatchlightLayout.minTouchTarget)
    }

    /// The Iris centre is 36 down from the card's top, and its inset + 22 in from the leading edge.
    func testHubCentre_isTheIrisCentre() {
        let card = CGRect(x: 17, y: 200, width: 368, height: 72)
        XCTAssertEqual(FocusRowView.hubCentre(of: card, irisLeadingInset: 24), CGPoint(x: 63, y: 236))
    }

    /// The card frame a host reports is rebuilt from the Iris centre and the card's size.
    func testCardFrame_fromIrisCentreAndSize() {
        XCTAssertEqual(FocusRowView.cardFrame(irisCentre: CGPoint(x: 63, y: 236),
                                              cardSize: CGSize(width: 368, height: 140),
                                              irisLeadingInset: 24),
                       CGRect(x: 17, y: 200, width: 368, height: 140))
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
        XCTAssertEqual(FocusRowView.hubCentre(of: card, irisLeadingInset: 24).y + 58, card.maxY + 22)
    }

    /// A 140pt card grows to 162: the marks' centres 162 - 36 = 126 below the Iris centre.
    func testRowY_tallCard_sitsOnTheGrownBottomEdge() {
        let card = CGRect(x: 20, y: 200, width: 353, height: 140)
        XCTAssertEqual(FocusRowView.rowY(cardFrame: card, visibleBottom: 852), 126)
        XCTAssertEqual(FocusRowView.hubCentre(of: card, irisLeadingInset: 24).y + 126, card.maxY + 22)
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
        let gap = xs[1] - xs[0]
        for i in 2..<xs.count {
            XCTAssertEqual(xs[i] - xs[i - 1], gap, accuracy: 0.0001, file: file, line: line)
        }
    }
}
