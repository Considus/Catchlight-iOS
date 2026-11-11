//
//  CornerRadiusRuleTests.swift
//  CatchlightTests (app module)
//
//  One corner radius for every box and control: 14. An item shorter than 42pt takes a third
//  of its height, rounded to the nearest point, so nothing reads as a pill. Parts inside a
//  control are concentric: the control's radius less the 3pt inset. The expected numbers are
//  the design's, written out here, not recomputed from the code under test.
//

import XCTest
import SwiftUI
@testable import Catchlight

final class CornerRadiusRuleTests: XCTestCase {

    func testBoxesAndControls_shareTheOneValue_14() {
        XCTAssertEqual(CatchlightLayout.controlRadius, 14)
        XCTAssertEqual(CatchlightLayout.surfaceRadius, 14)
        XCTAssertEqual(TakeCardStyle.cornerRadius, 14)
    }

    func testTallItem_takesTheFullRadius() {
        XCTAssertEqual(CatchlightLayout.cappedRadius(forHeight: 44), 14)
        XCTAssertEqual(CatchlightLayout.cappedRadius(forHeight: 42), 14)
        XCTAssertEqual(CatchlightLayout.cappedRadius(forHeight: 200), 14)
    }

    func testShortItem_takesAThirdOfItsHeight_toTheNearestPoint() {
        XCTAssertEqual(CatchlightLayout.cappedRadius(forHeight: 34), 11, "the Add button")
        XCTAssertEqual(CatchlightLayout.cappedRadius(forHeight: 28), 9, "the toggle track")
        XCTAssertEqual(CatchlightLayout.cappedRadius(forHeight: 30), 10)
        XCTAssertEqual(CatchlightLayout.cappedRadius(forHeight: 20), 7)
    }

    func testNoHeight_getsMoreThanAThird_beyondTheRoundingToAPoint() {
        for tenths in 30...600 {
            let h = CGFloat(tenths) / 10
            let r = CatchlightLayout.cappedRadius(forHeight: h)
            XCTAssertLessThanOrEqual(r, 14, "height \(h)")
            XCTAssertLessThanOrEqual(r, h / 3 + 0.5, "height \(h) gave \(r)")
        }
    }

    func testToggleKnob_isConcentricWithTheCappedTrack() {
        XCTAssertEqual(FlatToggleMetrics.knobRadius, 6, "track 28pt gives 9, less inset 3")
    }

    func testSegmentedThumb_isConcentricWithItsTrack() {
        XCTAssertEqual(FlatSegmentedMetrics.selectedRadius, 11, "track 14, less inset 3")
    }

    func testFocusRowMark_followsTheControlValue() {
        XCTAssertEqual(FocusRowView.markCornerRadius, 14)
    }

    private func rounded(_ rect: CGRect, _ radius: CGFloat) -> Path {
        Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
    }

    func testShapes_capAtAThirdOfTheirOwnHeight() {
        func rect(_ h: CGFloat) -> CGRect { CGRect(x: 0, y: 0, width: 100, height: h) }
        XCTAssertEqual(CatchlightShape.control.path(in: rect(44)), rounded(rect(44), 14))
        XCTAssertEqual(CatchlightShape.control.path(in: rect(34)), rounded(rect(34), 11))
        XCTAssertEqual(CatchlightShape.surface.path(in: rect(28)), rounded(rect(28), 9))
        XCTAssertEqual(CatchlightShape.surface.path(in: rect(120)), rounded(rect(120), 14))
    }

    func testInsetShape_keepsTheConcentricRule() {
        // A 28pt track gives 9. Inset by 3 the shape is a 22pt rounded rectangle at 6.
        let outer = CGRect(x: 0, y: 0, width: 100, height: 28)
        let inner = CatchlightShape.control.inset(by: 3).path(in: outer)
        XCTAssertEqual(inner, rounded(outer.insetBy(dx: 3, dy: 3), 6))
    }
}
