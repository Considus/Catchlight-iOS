//
//  FocusRowTimingTests.swift
//  CatchlightTests (app module)
//
//  When each part of the Focus row's open happens. Every mark takes the same L-shaped path:
//  straight down, then straight right, never both at once (Art Director's rule, 2026-11-11,
//  after Mark saw the far mark cut across the card). All four drop together over 220ms on an
//  ease-out, then all four leave together at one speed on the same overshoot-and-settle curve
//  (sideways only), the farthest taking 560ms. The close plays the whole open backwards 1.25 times
//  faster, except the slide left eases in with no settle.
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
    /// open (settle included: it is sideways only) or on the close.
    func testNoMarkMovesOnBothAxesAtOnce() {
        let end = T.openDuration(slots: slots)
        for kind in FocusRowView.MarkKind.allCases {
            var t = 0.0
            while t <= end {
                let drop = T.dropProgress(at: t)
                for (name, spread) in [("open", T.spreadProgress(kind, at: t, slots: slots)),
                                       ("close", T.closingSpreadProgress(kind, at: t, slots: slots))] {
                    XCTAssertFalse(drop < 1 && spread != 0,
                                   "\(kind) moves across while still dropping on the \(name) at \(t)s (drop \(drop), slide \(spread))")
                }
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

    /// Every mark leaves at the same speed: in the first half millisecond of the slide each covers
    /// the same number of points (within 1%).
    func testMarksLeaveTogether_atOneSpeed() {
        let t = T.drop + 0.0005
        let travelled = FocusRowView.MarkKind.allCases.map {
            T.spreadProgress($0, at: t, slots: slots) * Double(slots[$0.rawValue])
        }
        for points in travelled {
            XCTAssertEqual(points, travelled[0], accuracy: travelled[0] * 0.01)
        }
    }

    /// Each mark settles: past its slot by the same share of its travel (about 4.9%: Important
    /// about 11.7pt, Note 2.9), then back, landing exactly in its slot.
    func testEachMarkSettles_bySameShareOfItsTravel() {
        for kind in FocusRowView.MarkKind.allCases {
            let duration = T.spreadDuration(travel: slots[kind.rawValue], slots: slots)
            var peak = 0.0
            var t = T.drop
            while t <= T.drop + duration {
                peak = max(peak, T.spreadProgress(kind, at: t, slots: slots))
                t += 0.0005
            }
            XCTAssertEqual(peak, 1.0487, accuracy: 0.001, "\(kind) does not settle by the same share")
            XCTAssertEqual(T.spreadProgress(kind, at: T.drop + duration, slots: slots), 1, accuracy: 1e-9)
        }
        XCTAssertEqual(0.0487 * 240, 11.7, accuracy: 0.05)
    }

    /// Note settles first and Important last.
    func testNearMarksLandFirst() {
        let ends = FocusRowView.MarkKind.allCases.map { T.spreadDuration(travel: slots[$0.rawValue], slots: slots) }
        XCTAssertLessThan(ends[FocusRowView.MarkKind.note.rawValue], ends[FocusRowView.MarkKind.task.rawValue])
        XCTAssertLessThan(ends[FocusRowView.MarkKind.task.rawValue], ends[FocusRowView.MarkKind.remind.rawValue])
        XCTAssertLessThan(ends[FocusRowView.MarkKind.remind.rawValue], ends[FocusRowView.MarkKind.important.rawValue])
    }

    /// The close has no settle: each mark only ever moves left, never past its slot, and never
    /// past the Iris.
    func testClose_slidesLeftWithNoTwitchOrSettle() {
        for kind in FocusRowView.MarkKind.allCases {
            var elapsed = 0.0
            var last = T.closingSpreadProgress(kind, at: T.closeTime(elapsed: 0, slots: slots), slots: slots)
            XCTAssertEqual(last, 1, accuracy: 1e-9)
            while elapsed <= T.closeDuration(slots: slots) {
                let now = T.closingSpreadProgress(kind, at: T.closeTime(elapsed: elapsed, slots: slots), slots: slots)
                XCTAssertLessThanOrEqual(now, last + 1e-12, "\(kind) moves right on the close at \(elapsed)s")
                XCTAssertGreaterThanOrEqual(now, 0)
                last = now
                elapsed += 0.002
            }
        }
    }

    /// The farthest mark's slide takes 560ms: 220 + 560 = 780ms for the whole open.
    func testOpen_takes780ms() {
        XCTAssertEqual(T.openDuration(slots: slots), 0.780, accuracy: 1e-9)
        XCTAssertNotEqual(T.spreadProgress(.important, at: 0.779, slots: slots), 1, accuracy: 1e-6)
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
