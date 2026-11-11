//
//  FocusRowTimingTests.swift
//  CatchlightTests (app module)
//
//  When each part of the Focus row's open happens. Every mark takes the same L-shaped path:
//  straight down, then straight right, never both at once (Art Director's rule, 2026-11-11,
//  after Mark saw the far mark cut across the card). All four drop together over 220ms on an
//  ease-out, then all four slide right together at one speed, set so the farthest mark's slide
//  takes 560ms; each eases out only over its own last stretch. The close plays the whole open
//  backwards 1.25 times faster.
//

import XCTest
@testable import Catchlight

final class FocusRowTimingTests: XCTestCase {

    private typealias T = FocusRowView.Timing
    /// The marks' slots on a phone: 60, 120, 180 and 240pt right of the Iris centre.
    private let slots: [CGFloat] = [60, 120, 180, 240]

    func testDrop_takes220ms_easingOut() {
        XCTAssertEqual(T.drop, 0.220, accuracy: 1e-9)
        XCTAssertEqual(T.dropProgress(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(T.dropProgress(at: 0.220), 1, accuracy: 1e-9)
        // Ease-out: well past halfway at half time.
        XCTAssertGreaterThan(T.dropProgress(at: 0.110), 0.8)
    }

    func testMarksGrowFrom85PercentOverTheDrop() {
        XCTAssertEqual(T.markScale(at: 0), 0.85, accuracy: 1e-9)
        XCTAssertEqual(T.markScale(at: 0.220), 1, accuracy: 1e-9)
    }

    func testMarksFadeInOverTheFirst80ms() {
        XCTAssertEqual(T.markOpacity(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(T.markOpacity(at: 0.040), 0.5, accuracy: 1e-9)
        XCTAssertEqual(T.markOpacity(at: 0.080), 1, accuracy: 1e-9)
    }

    /// The rule Mark asked for: no mark ever moves down and across at the same moment, on the
    /// open or (since it is the open backwards) on the close.
    func testNoMarkMovesOnBothAxesAtOnce() {
        let end = T.openDuration(slots: slots)
        for kind in FocusRowView.MarkKind.allCases {
            var t = 0.0
            while t <= end {
                let drop = T.dropProgress(at: t)
                let spread = T.spreadProgress(kind, at: t, slots: slots)
                XCTAssertFalse(drop < 1 && spread > 0,
                               "\(kind) slides while still dropping at \(t)s (drop \(drop), slide \(spread))")
                t += 0.005
            }
        }
    }

    /// All four start sliding together the moment the drop ends.
    func testEveryMarkStartsSliding_whenTheDropEnds() {
        for kind in FocusRowView.MarkKind.allCases {
            XCTAssertEqual(T.spreadProgress(kind, at: T.drop, slots: slots), 0, accuracy: 1e-9)
            XCTAssertGreaterThan(T.spreadProgress(kind, at: T.drop + 0.010, slots: slots), 0,
                                 "\(kind) waits before sliding")
        }
    }

    /// The same speed for every mark while they slide together: after 50ms of sliding each has
    /// travelled the same number of points.
    func testMarksSlideTogether_atOneSpeed() {
        let t = T.drop + 0.050
        let travelled = FocusRowView.MarkKind.allCases.map {
            T.spreadProgress($0, at: t, slots: slots) * Double(slots[$0.rawValue])
        }
        for points in travelled {
            XCTAssertEqual(points, travelled[0], accuracy: 1e-6)
        }
    }

    /// Note stops first and Important last, and none overshoots its slot.
    func testNearMarksStopFirst_withNoOvershoot() {
        let ends = FocusRowView.MarkKind.allCases.map { kind -> Double in
            var t = T.drop
            while T.spreadProgress(kind, at: t, slots: slots) < 1 { t += 0.001 }
            return t
        }
        XCTAssertLessThan(ends[FocusRowView.MarkKind.note.rawValue], ends[FocusRowView.MarkKind.task.rawValue])
        XCTAssertLessThan(ends[FocusRowView.MarkKind.task.rawValue], ends[FocusRowView.MarkKind.remind.rawValue])
        XCTAssertLessThan(ends[FocusRowView.MarkKind.remind.rawValue], ends[FocusRowView.MarkKind.important.rawValue])
        for kind in FocusRowView.MarkKind.allCases {
            var t = 0.0
            while t <= 1 {
                XCTAssertLessThanOrEqual(T.spreadProgress(kind, at: t, slots: slots), 1 + 1e-9)
                t += 0.005
            }
        }
    }

    /// The farthest mark's slide takes 560ms: 220 + 560 = 780ms for the whole open.
    func testOpen_takes780ms() {
        XCTAssertEqual(T.openDuration(slots: slots), 0.780, accuracy: 1e-9)
        XCTAssertLessThan(T.spreadProgress(.important, at: 0.779, slots: slots), 1)
        XCTAssertEqual(T.spreadProgress(.important, at: 0.780, slots: slots), 1, accuracy: 1e-9)
    }

    /// The close plays the whole open backwards at 1.25 times: 780 / 1.25 = 624ms.
    func testClose_playsTheWholeOpenBackwards() {
        XCTAssertEqual(T.closeDuration(slots: slots), 0.624, accuracy: 1e-9)
        XCTAssertEqual(T.closeTime(elapsed: 0, slots: slots), 0.780, accuracy: 1e-9,
                       "The close does not start at the end of the open")
        XCTAssertEqual(T.closeTime(elapsed: 0.4, slots: slots), 0.280, accuracy: 1e-9,
                       "The close does not follow the whole open backwards")
    }
}
