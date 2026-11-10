//
//  FlatToggleGestureTests.swift
//  CatchlightAppTests
//
//  What the flat toggle does when a horizontal drag on its track lifts. Measured on the
//  native switch (the one used before the redesign) on the iPhone 18 Pro simulator, 10 runs
//  each way: a drag that goes out 12pt and comes back to within 3pt of where it started
//  still flips the switch. So a drag whose pan began and ended with little net travel flips
//  the flat toggle too, as a tap does.
//

import XCTest
@testable import Catchlight

final class FlatToggleGestureTests: XCTestCase {

    func testDragPastTheThreshold_setsTheSideItWentTo() {
        XCTAssertEqual(FlatToggleGesture.outcome(forTravel: 12), .swipe(toTheRight: true))
        XCTAssertEqual(FlatToggleGesture.outcome(forTravel: -12), .swipe(toTheRight: false))
        XCTAssertEqual(FlatToggleGesture.outcome(forTravel: 22), .swipe(toTheRight: true))
    }

    func testDragThatBeganButEndedWithLittleTravel_flipsLikeATap() {
        XCTAssertEqual(FlatToggleGesture.outcome(forTravel: 0), .flip)
        XCTAssertEqual(FlatToggleGesture.outcome(forTravel: 3), .flip)
        XCTAssertEqual(FlatToggleGesture.outcome(forTravel: -3), .flip)
        XCTAssertEqual(FlatToggleGesture.outcome(forTravel: 10), .flip)
        XCTAssertEqual(FlatToggleGesture.outcome(forTravel: -10), .flip)
    }
}
