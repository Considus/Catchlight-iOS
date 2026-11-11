//
//  IconMotionTests.swift
//  CatchlightTests (app module)
//
//  The icon morphs: every Iris shape is exactly five segments (padded with its last end
//  point), the interpolation endpoints are the shapes themselves, the widgets' path is
//  unchanged, the Sequence icon is today's icon when closed, and Reduce Motion drops movement.
//

import XCTest
import SwiftUI
@testable import Catchlight

final class IconMotionTests: XCTestCase {

    private let shapes: [IrisInnerShape] = [.note, .task, .reminder, .audio, .image, .fourDots]

    /// The shapes as they were on main, before the morph, written out independently.
    private let original: [IrisInnerShape: [[CGFloat]]] = [
        .note: [[7.5, 9, 16.5, 9], [7.5, 12, 16.5, 12], [7.5, 15, 13, 15]],
        .task: [[7.2, 12.4, 10.4, 15.6], [10.4, 15.6, 16.8, 8.6]],
        .reminder: [[12, 12.6, 12, 6.2], [12, 12.6, 16.6, 15]],
        .audio: [[7, 10.6, 7, 13.4], [9.5, 8.2, 9.5, 15.8], [12, 6.2, 12, 17.8], [14.5, 8.6, 14.5, 15.4], [17, 10.6, 17, 13.4]],
        .image: [[5.6, 17, 10, 12], [10, 12, 13.2, 15.6], [12.2, 14.6, 14.8, 11.6], [14.8, 11.6, 18.4, 17], [16.2, 7.2, 17.4, 7.2]],
        .fourDots: [[9, 9, 9, 9], [15, 9, 15, 9], [9, 15, 9, 15], [15, 15, 15, 15]],
    ]

    func testEveryShapeIsFiveSegments_paddedWithTheLastEndPoint() {
        for shape in shapes {
            let segs = IrisGeometry.morphSegments(shape)
            let real = original[shape]!
            XCTAssertEqual(segs.count, 5, "\(shape)")
            XCTAssertEqual(Array(segs.prefix(real.count)), real, "\(shape)")
            let end = Array(real.last![2...3])
            for pad in segs.dropFirst(real.count) { XCTAssertEqual(pad, end + end, "\(shape)") }
            XCTAssertEqual(IrisGeometry.realSegmentCount(shape), real.count)
        }
    }

    func testInterpolationEndpointsEqualTheShapes() {
        let lit = IrisLight.allCases.reduce(into: [IrisLight: Bool]()) { $0[$1] = false }
        for a in shapes { for b in shapes {
            let va = IrisMorphState(shape: a, lit: lit).vector.values
            let vb = IrisMorphState(shape: b, lit: lit).vector.values
            // Interpolation of numbers is exact only to rounding; SwiftUI sets the final value itself.
            func close(_ x: [Double], _ y: [Double]) {
                XCTAssertEqual(x.count, y.count)
                for (p, q) in zip(x, y) { XCTAssertEqual(p, q, accuracy: 1e-12, "\(a) to \(b)") }
            }
            close(zip(va, vb).map { $0 + ($1 - $0) * 0 }, va)
            close(zip(va, vb).map { $0 + ($1 - $0) * 1 }, vb)
            XCTAssertEqual(Array(vb.prefix(20)), IrisGeometry.morphSegments(b).flatMap { $0.map(Double.init) })
            XCTAssertEqual(vb[25], Double(IrisGeometry.innerWidth(b)))
        } }
    }

    func testPaddingIsHiddenAndLitLightsAreOne() {
        var lit = IrisLight.allCases.reduce(into: [IrisLight: Bool]()) { $0[$1] = false }
        lit[.task] = true
        let v = IrisMorphState(shape: .task, lit: lit).vector.values
        XCTAssertEqual(Array(v[20...24]), [1, 1, 0, 0, 0])
        XCTAssertEqual(Array(v[26...31]), [0, 1, 0, 0, 0, 0])
        XCTAssertEqual(Array(IrisMorphState(shape: .fourDots, lit: lit).vector.values[20...24]), [1, 1, 1, 1, 0])
    }

    /// The widgets draw `innerPath`: it must still be today's path for every shape.
    func testWidgetInnerPathUnchanged() {
        func p(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> CGPoint {
            CGPoint(x: (22 + (x - 12) * 1.3) * s, y: (22 + (y - 12) * 1.3) * s)
        }
        for shape in shapes {
            var expected = Path()
            for seg in original[shape]! {
                expected.move(to: p(seg[0], seg[1], 2)); expected.addLine(to: p(seg[2], seg[3], 2))
            }
            XCTAssertEqual(IrisGeometry.innerPath(shape, scale: 2), expected, "\(shape)")
        }
    }

    func testSequenceClosedIsTodaysIcon_openHidesTheMiddleLine() {
        let rect = CGRect(x: 0, y: 0, width: 22, height: 22)
        XCTAssertEqual(SequenceLines(progress: 0).path(in: rect), ToolbarGlyph.sequence.path(in: rect))
        var cross = Path()
        let s: CGFloat = 22 / 24
        for l in [[6.5, 6.5, 17.5, 17.5], [6.5, 17.5, 17.5, 6.5]] as [[CGFloat]] {
            cross.move(to: CGPoint(x: l[0] * s, y: l[1] * s)); cross.addLine(to: CGPoint(x: l[2] * s, y: l[3] * s))
        }
        XCTAssertEqual(SequenceLines(progress: 1).path(in: rect), cross)
    }

    func testReduceMotionDropsMovement() {
        XCTAssertNil(CatchlightMotion.movement(CatchlightMotion.shape, reduceMotion: true))
        XCTAssertNotNil(CatchlightMotion.movement(CatchlightMotion.shape, reduceMotion: false))
    }

    // MARK: - One change, one morph (art director 2026-11-11)

    @MainActor
    func testAFocusRowCommit_holdsThatTakesIrisStill_forAMomentOnly() {
        let id = UUID(), other = UUID()
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        IrisMorphHold.hold(id, now: t0)
        XCTAssertTrue(IrisMorphHold.isHeld(id, now: t0.addingTimeInterval(0.5)), "The card should switch under the row's fade")
        XCTAssertFalse(IrisMorphHold.isHeld(other, now: t0.addingTimeInterval(0.5)), "Another Take's Iris still morphs")
        XCTAssertFalse(IrisMorphHold.isHeld(id, now: t0.addingTimeInterval(IrisMorphHold.window + 0.01)),
                       "After the hold, a later change to the same Take morphs again")
    }

    @MainActor
    func testWithoutAHold_theIrisMorphs() {
        XCTAssertFalse(IrisMorphHold.isHeld(UUID(), now: Date()))
        XCTAssertNotNil(IrisView.morphAnimation(held: false, reduceMotion: false))
        XCTAssertNil(IrisView.morphAnimation(held: true, reduceMotion: false), "A held Iris switches with no animation")
    }
}
