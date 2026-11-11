//
//  OnboardingPointMarkTests.swift
//  CatchlightTests (app module)
//
//  The drawings beside the points on "A few things worth knowing" are squares where the thing
//  they show is a square: the Iris, and the tile it sits in.
//

import XCTest
@testable import Catchlight

final class OnboardingPointMarkTests: XCTestCase {

    func testIrisTileIsSquare() {
        XCTAssertEqual(PointMark.tileSize.width, PointMark.tileSize.height, accuracy: 0.5)
    }

    func testIrisIsSquare() {
        // The Iris is drawn in a square frame of this one diameter.
        XCTAssertGreaterThan(PointMark.irisDiameter, 0)
        XCTAssertLessThanOrEqual(PointMark.irisDiameter + 2 * PointMark.tileInset, PointMark.tileSize.width)
        XCTAssertLessThanOrEqual(PointMark.irisDiameter + 2 * PointMark.tileInset, PointMark.tileSize.height)
    }

    func testMarkBoxIsSquare() {
        XCTAssertEqual(PointMark.markSize.width, PointMark.markSize.height, accuracy: 0.5)
    }
}
