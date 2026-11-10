//
//  FlatControlMetricsTests.swift
//  CatchlightTests (app module)
//
//  The flat toggle and the flat segmented control are rounded rectangles with a concentric
//  inner shape: the inner corner radius is the control radius less the inset, so the gap
//  between the two edges is even all round. The expected numbers are the design's: control
//  radius 10, inset 3, inner radius 7.
//

import XCTest
@testable import Catchlight

final class FlatControlMetricsTests: XCTestCase {

    func testControlRadius_isTen_andSurfaceRadius_isSixteen() {
        XCTAssertEqual(CatchlightLayout.controlRadius, 10)
        XCTAssertEqual(CatchlightLayout.surfaceRadius, 16)
    }

    func testToggleKnob_isConcentricWithItsTrack() {
        XCTAssertEqual(FlatToggleMetrics.knobInset, 3)
        XCTAssertEqual(FlatToggleMetrics.knobRadius, 7, "control radius 10 less inset 3")
        XCTAssertEqual(FlatToggleMetrics.knobSize, 22, "track height 28 less an inset each side")
    }

    func testToggleTrack_isARoundedRectangleNotAPill() {
        XCTAssertLessThan(CatchlightLayout.controlRadius, FlatToggleMetrics.trackHeight / 2,
                          "a radius of half the height would be a pill")
    }

    func testToggleTapTarget_isAtLeast44By44() {
        XCTAssertGreaterThanOrEqual(FlatToggleMetrics.tapTarget.width, 44)
        XCTAssertGreaterThanOrEqual(FlatToggleMetrics.tapTarget.height, 44)
    }

    func testSegmentedControl_selectedSegmentIsConcentricWithItsContainer() {
        XCTAssertEqual(FlatSegmentedMetrics.inset, 3)
        XCTAssertEqual(FlatSegmentedMetrics.selectedRadius, 7, "control radius 10 less inset 3")
        XCTAssertGreaterThanOrEqual(FlatSegmentedMetrics.segmentHeight, 44)
    }
}
