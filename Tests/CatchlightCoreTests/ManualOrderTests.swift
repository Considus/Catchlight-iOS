//
//  ManualOrderTests.swift
//  CatchlightCoreTests
//
//  The manual timeline arrangement (D-195). The gesture needs a device; this is the
//  arithmetic underneath it, which does not.
//

import XCTest
@testable import CatchlightCore

final class ManualOrderTests: XCTestCase {

    /// Takes a fixed number of seconds apart, oldest first, with stable ids so a
    /// failure names the same Take every run.
    private func makeTakes(_ count: Int, spacing: TimeInterval = 60) -> [Take] {
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        return (0..<count).map { i in
            Take(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", i))!,
                 createdAt: base.addingTimeInterval(Double(i) * spacing),
                 modifiedAt: base.addingTimeInterval(Double(i) * spacing),
                 blocks: [.textLine("take \(i)")])
        }
    }

    /// The VM's own newest-first sort, duplicated here so the equivalence test below
    /// compares against the REAL date order rather than against itself.
    private func dateOrderNewestFirst(_ takes: [Take]) -> [Take] {
        takes.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString > $1.id.uuidString
        }
    }

    // MARK: - The headline property

    // Nothing dragged ⇒ manual mode is IDENTICAL to date order, in BOTH directions.
    // This is what lets the owner turn the setting on without the timeline moving
    // under him, and it is the reason `manualOrder` is nil rather than a migrated rank.
    func testUndraggedArrangementMatchesDateOrder_bothDirections() {
        let takes = makeTakes(12).shuffled()
        let newestFirst = dateOrderNewestFirst(takes)

        let canonical = ManualOrder.arranged(takes)
        XCTAssertEqual(canonical.map(\.id), Array(newestFirst.reversed()).map(\.id),
                       "oldest-first manual must equal oldest-first date order")
        XCTAssertEqual(canonical.reversed().map(\.id), newestFirst.map(\.id),
                       "newest-first manual must equal newest-first date order")
    }

    // D-226 (the Storyboard's Obie): `arranged` is handed a Take that has never been
    // in a manual arrangement — the Obie is not on the timeline's arrangeable list.
    // It must be PRESENT (a drop here silently reproduces the invisible-Obie bug in
    // Manual mode only) and sit at its date position among dragged Takes, per the
    // number-line rule: an undragged Take's effective order IS its createdAt.
    func testTakeWithNoManualPosition_isKeptAndSitsAtItsDatePosition() {
        var takes = makeTakes(5)
        // Drag three of them to explicit positions far below any epoch (a renumbered
        // arrangement); leave takes[1] (the "Obie") and takes[4] undragged.
        takes[0].manualOrder = 1.0
        takes[2].manualOrder = 2.0
        takes[3].manualOrder = 3.0

        let canonical = ManualOrder.arranged(takes)
        XCTAssertEqual(canonical.count, takes.count, "arranged must never drop a Take")
        XCTAssertTrue(canonical.contains { $0.id == takes[1].id },
                      "a Take with no manual position must still be present")
        // Undragged Takes carry epoch-scale effective orders, so they sort AFTER the
        // renumbered ones (the "now" end) and by date between themselves — the same
        // rule as a new or synced Take, not an arbitrary landing.
        XCTAssertEqual(canonical.map(\.id),
                       [takes[0].id, takes[2].id, takes[3].id, takes[1].id, takes[4].id],
                       "undragged Takes sort to the now end, in date order between themselves")
    }

    // Same-instant creations tie on createdAt, and Swift's sort is not stable — the id
    // tie-break is what stops tied rows shuffling between reloads.
    func testSameInstantTakesOrderDeterministically() {
        let instant = Date(timeIntervalSince1970: 1_760_000_000)
        let takes = (0..<8).map { i in
            Take(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", i))!,
                 createdAt: instant, modifiedAt: instant, blocks: [.textLine("t\(i)")])
        }
        let once = ManualOrder.arranged(takes.shuffled()).map(\.id)
        let twice = ManualOrder.arranged(takes.shuffled()).map(\.id)
        XCTAssertEqual(once, twice)
    }

    // MARK: - Moving

    /// Apply the returned values and re-sort, which is exactly what the app does after
    /// `moveTake` writes and `reload()` runs.
    private func applying(_ values: [UUID: Double], to takes: [Take]) -> [Take] {
        ManualOrder.arranged(takes.map { take in
            guard let order = values[take.id] else { return take }
            var moved = take
            moved.manualOrder = order
            return moved
        })
    }

    func testMoveToTop() {
        let takes = makeTakes(5)
        let last = takes[4]
        let values = ManualOrder.reorder(takes, moving: last.id, to: 0)
        XCTAssertEqual(values.count, 1, "one Take is written, not the whole timeline")
        XCTAssertEqual(applying(values, to: takes).map(\.id),
                       [takes[4], takes[0], takes[1], takes[2], takes[3]].map(\.id))
    }

    func testMoveToBottom() {
        let takes = makeTakes(5)
        let values = ManualOrder.reorder(takes, moving: takes[0].id, to: 4)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(applying(values, to: takes).map(\.id),
                       [takes[1], takes[2], takes[3], takes[4], takes[0]].map(\.id))
    }

    func testMoveIntoTheMiddle() {
        let takes = makeTakes(5)
        let values = ManualOrder.reorder(takes, moving: takes[0].id, to: 2)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(applying(values, to: takes).map(\.id),
                       [takes[1], takes[2], takes[0], takes[3], takes[4]].map(\.id))
    }

    // Dropped where it was picked up: nothing is written, so no Take is re-encrypted
    // and pushed to the cloud for a gesture that changed nothing.
    func testDropAtOriginalPositionWritesNothing() {
        let takes = makeTakes(5)
        XCTAssertTrue(ManualOrder.reorder(takes, moving: takes[2].id, to: 2).isEmpty)
    }

    func testMovingAnUnknownTakeWritesNothing() {
        XCTAssertTrue(ManualOrder.reorder(makeTakes(3), moving: UUID(), to: 0).isEmpty)
    }

    func testSingleTakeHasNoMeaningfulPosition() {
        let takes = makeTakes(1)
        XCTAssertTrue(ManualOrder.reorder(takes, moving: takes[0].id, to: 0).isEmpty)
    }

    // An arrangement survives repeated moves rather than drifting — each drag is
    // interpolated against the CURRENT values, not the original dates.
    func testRepeatedMovesCompose() {
        var takes = makeTakes(6)
        func move(_ index: Int, to destination: Int) {
            let id = ManualOrder.arranged(takes)[index].id
            let values = ManualOrder.reorder(takes, moving: id, to: destination)
            takes = takes.map { take in
                guard let order = values[take.id] else { return take }
                var moved = take; moved.manualOrder = order; return moved
            }
        }
        move(5, to: 0)   // last to top
        move(5, to: 1)   // new last to second
        move(0, to: 5)   // top to bottom
        let ids = ManualOrder.arranged(takes).map(\.id)
        XCTAssertEqual(Set(ids), Set(takes.map(\.id)), "no Take lost or duplicated")
        XCTAssertEqual(ids.count, 6)
    }

    // MARK: - Where a new or synced Take lands

    // A Take with no position sorts to the "now" end (owner 2026-08-14) — the same rule
    // covers one created locally and one arriving from another device, because neither
    // carries a manual position.
    func testUnpositionedTakeLandsAtTheNowEnd() {
        var takes = makeTakes(4)
        // Hand-arrange: move the oldest to the bottom.
        let values = ManualOrder.reorder(takes, moving: takes[0].id, to: 3)
        takes = takes.map { take in
            guard let order = values[take.id] else { return take }
            var moved = take; moved.manualOrder = order; return moved
        }
        let arrived = Take(createdAt: Date(timeIntervalSince1970: 1_760_099_999),
                           modifiedAt: Date(timeIntervalSince1970: 1_760_099_999),
                           blocks: [.textLine("from sync")])
        XCTAssertNil(arrived.manualOrder)
        XCTAssertEqual(ManualOrder.arranged(takes + [arrived]).last?.id, arrived.id)
    }

    // MARK: - Precision

    // Halving the same gap eventually lands the midpoint on a neighbour, at which point
    // the arrangement would silently stop responding. It renumbers instead — the one
    // path that writes more than one Take — and the visible order is preserved across it.
    func testExhaustedPrecisionRenumbersAndKeepsTheOrder() {
        var takes = makeTakes(3)
        // Squeeze two neighbours to adjacent Doubles: no midpoint exists between them.
        let squeezed = 1_760_000_000.0
        takes[0].manualOrder = squeezed
        takes[1].manualOrder = squeezed.nextUp
        takes[2].manualOrder = squeezed.nextUp.nextUp

        let values = ManualOrder.reorder(takes, moving: takes[2].id, to: 1)
        XCTAssertEqual(values.count, 3, "a renumber rewrites the whole arrangement")
        XCTAssertEqual(applying(values, to: takes).map(\.id),
                       [takes[0], takes[2], takes[1]].map(\.id))
        // Renumbered values are small integers, far below any epoch — so a Take created
        // afterwards (carrying nil) still sorts to the now end.
        XCTAssertTrue(values.values.allSatisfy { $0 < 1_000 })
    }

    // MARK: - Payload

    func testManualOrderRoundTripsThroughJSON() throws {
        var take = makeTakes(1)[0]
        take.manualOrder = 42.5
        let decoded = try PlatformJSON.decode(Take.self, from: PlatformJSON.encode(take))
        XCTAssertEqual(decoded.manualOrder, 42.5)
        XCTAssertEqual(decoded, take)
    }

    // An undragged Take must not put the key in the payload at all — a v3 Take nobody
    // has moved serialises as its v2 self apart from the version number.
    func testUndraggedTakeOmitsTheKey() throws {
        let json = String(data: try PlatformJSON.encode(makeTakes(1)[0]), encoding: .utf8)!
        XCTAssertFalse(json.contains("manualOrder"))
    }

    // A v2 payload predates the field: it decodes as nil, i.e. "sits at its date
    // position", so an existing cloud folder keeps working and nothing jumps. Built by
    // re-stamping a real encoded Take rather than by hand — a hand-written block payload
    // would test my typing, not the decoder.
    func testV2PayloadDecodesWithNoManualOrder() throws {
        let encoded = String(data: try PlatformJSON.encode(makeTakes(1)[0]), encoding: .utf8)!
        XCTAssertFalse(encoded.contains("manualOrder"), "an undragged Take carries no key")
        let v2 = encoded.replacingOccurrences(of: "\"schemaVersion\":3", with: "\"schemaVersion\":2")
        XCTAssertTrue(v2.contains("\"schemaVersion\":2"))
        let decoded = try PlatformJSON.decode(Take.self, from: Data(v2.utf8))
        XCTAssertNil(decoded.manualOrder)
        XCTAssertEqual(decoded.schemaVersion, 2, "decoding must not silently re-stamp a v2 payload")
    }
}
