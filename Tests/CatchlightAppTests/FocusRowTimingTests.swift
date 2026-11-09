//
//  FocusRowTimingTests.swift
//  CatchlightTests (app module)
//
//  When each part of the Focus row's open happens: the drop and the card's growth over
//  340ms, the marks fading in over the first 80ms, the far marks peeling off first, each
//  slide lasting 3.9ms per point travelled (280ms at least), about 1.06s in all, and the
//  close playing the whole open backwards 1.25 times faster.
//

import XCTest
@testable import Catchlight

final class FocusRowTimingTests: XCTestCase {

    private typealias T = FocusRowView.Timing
    /// The marks' slots on a phone: 60, 120, 180 and 240pt right of the Iris centre.
    private let slots: [CGFloat] = [60, 120, 180, 240]

    func testDrop_takes340ms() {
        XCTAssertEqual(T.drop, 0.340, accuracy: 1e-9)
        XCTAssertEqual(T.dropProgress(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(T.dropProgress(at: 0.170), 0.5, accuracy: 1e-9)
        XCTAssertEqual(T.dropProgress(at: 0.340), 1, accuracy: 1e-9)
    }

    func testMarksGrowFrom85PercentOverTheDrop() {
        XCTAssertEqual(T.markScale(at: 0), 0.85, accuracy: 1e-9)
        XCTAssertEqual(T.markScale(at: 0.340), 1, accuracy: 1e-9)
    }

    func testMarksFadeInOverTheFirst80ms() {
        XCTAssertEqual(T.markOpacity(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(T.markOpacity(at: 0.040), 0.5, accuracy: 1e-9)
        XCTAssertEqual(T.markOpacity(at: 0.080), 1, accuracy: 1e-9)
        XCTAssertEqual(T.markOpacity(at: 0.200), 1, accuracy: 1e-9)
    }

    func testFarMarksPeelOffFirst() {
        XCTAssertEqual(T.spreadStart(.important), 0.120, accuracy: 1e-9)
        XCTAssertEqual(T.spreadStart(.remind), 0.185, accuracy: 1e-9)
        XCTAssertEqual(T.spreadStart(.task), 0.250, accuracy: 1e-9)
        XCTAssertEqual(T.spreadStart(.note), 0.340, accuracy: 1e-9)
    }

    /// 3.9ms per point travelled, never under 280ms: Note 280, Task 468, Reminder 702 and
    /// Important 936ms at the standard slots.
    func testSlideDuration_followsTheDistance() {
        XCTAssertEqual(T.spreadDuration(travel: 60), 0.280, accuracy: 1e-9)
        XCTAssertEqual(T.spreadDuration(travel: 120), 0.468, accuracy: 1e-9)
        XCTAssertEqual(T.spreadDuration(travel: 180), 0.702, accuracy: 1e-9)
        XCTAssertEqual(T.spreadDuration(travel: 240), 0.936, accuracy: 1e-9)
    }

    /// Important lands last: 120 + 936 = 1056ms.
    func testOpen_takesAbout1060ms() {
        XCTAssertEqual(T.openDuration(slots: slots), 1.056, accuracy: 1e-9)
    }

    /// The close plays the whole open backwards at 1.25 times: 1056 / 1.25 = 844.8ms.
    func testClose_playsTheWholeOpenBackwards() {
        XCTAssertEqual(T.closeDuration(slots: slots), 0.8448, accuracy: 1e-9)
        XCTAssertEqual(T.closeTime(elapsed: 0, slots: slots), 1.056, accuracy: 1e-9,
                       "The close does not start at the end of the open")
        XCTAssertEqual(T.closeTime(elapsed: 0.4, slots: slots), 0.556, accuracy: 1e-9,
                       "The close does not follow the whole open backwards")
    }

    /// Marks slide while still dropping: Important starts at 120ms, inside the 340ms drop.
    func testSpreadOverlapsTheDrop() {
        XCTAssertGreaterThan(T.spreadProgress(.important, at: 0.300, travel: 240), 0)
        XCTAssertLessThan(T.dropProgress(at: 0.300), 1)
    }
}
