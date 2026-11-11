//
//  FlatControlMetricsTests.swift
//  CatchlightTests (app module)
//
//  The flat toggle and the flat segmented control are rounded rectangles with a concentric
//  inner shape: the inner corner radius is the outer radius less the inset, so the gap
//  between the two edges is even all round. The expected numbers are the design's: radius 14
//  (a third of height for a short item), inset 3. The 28pt track gives 9 and its knob 6.
//  The 44pt segmented track gives 14 and its thumb 11.
//

import XCTest
@testable import Catchlight

final class FlatControlMetricsTests: XCTestCase {

    func testControlRadius_andSurfaceRadius_areBothFourteen() {
        XCTAssertEqual(CatchlightLayout.controlRadius, 14)
        XCTAssertEqual(CatchlightLayout.surfaceRadius, 14)
    }

    func testToggleKnob_isConcentricWithItsTrack() {
        XCTAssertEqual(FlatToggleMetrics.knobInset, 3)
        XCTAssertEqual(FlatToggleMetrics.knobRadius, 6, "track radius 9 (a third of 28) less inset 3")
        XCTAssertEqual(FlatToggleMetrics.knobSize, 22, "track height 28 less an inset each side")
    }

    func testToggleTrack_isARoundedRectangleNotAPill() {
        XCTAssertLessThanOrEqual(CatchlightLayout.cappedRadius(forHeight: FlatToggleMetrics.trackHeight),
                                 FlatToggleMetrics.trackHeight / 3 + 0.5,
                                 "a short control's corner is at most a third of its height, rounded")
    }

    func testToggleTapTarget_isAtLeast44By44() {
        XCTAssertGreaterThanOrEqual(FlatToggleMetrics.tapTarget.width, 44)
        XCTAssertGreaterThanOrEqual(FlatToggleMetrics.tapTarget.height, 44)
    }

    func testSegmentedControl_selectedSegmentIsConcentricWithItsContainer() {
        XCTAssertEqual(FlatSegmentedMetrics.inset, 3)
        XCTAssertEqual(FlatSegmentedMetrics.selectedRadius, 11, "track radius 14 less inset 3")
        XCTAssertGreaterThanOrEqual(FlatSegmentedMetrics.segmentHeight, 44)
    }
}
