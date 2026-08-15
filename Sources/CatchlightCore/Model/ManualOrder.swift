//
//  ManualOrder.swift
//  CatchlightCore
//
//  The MANUAL timeline arrangement (D-195). The timeline can be arranged by Date or
//  by hand; this is the sort and the drag arithmetic behind the second one. Lives in
//  Core, not the app target, so the ordering rules are unit-testable without a
//  simulator — the gesture needs a device, the maths does not.
//
//  THE NUMBER LINE. `Take.manualOrder` is a sparse fractional index. A Take that has
//  never been dragged carries `nil`, and the sort substitutes its `createdAt` as
//  epoch seconds — so untouched Takes lie on the number line exactly where the date
//  sort already put them. Two consequences fall straight out of that, and both are
//  the point:
//
//    • Turning Manual on changes NOTHING until something is dragged. There is no
//      migration write, no mass re-encrypt, and no "why did my timeline jump".
//    • A newly created Take, or one arriving from sync, carries nil — so its epoch
//      places it at the "now" end, which is where the owner asked new Takes to land
//      (2026-08-14). No special case in the caller; it is the same rule.
//
//  ASCENDING IS ALWAYS OLDEST-FIRST. The canonical arrangement has one direction.
//  The Order setting (oldest/newest) reverses the RENDERED list, never the stored
//  values, so flipping it twice returns the arrangement exactly — which is what the
//  owner asked for when he kept oldest/newest adjustable alongside Manual.
//
//  WHY FRACTIONAL AND NOT A 0…n RANK. `manualOrder` rides the encrypted payload, so
//  writing it re-seals and pushes that Take. A dense rank renumbers the whole
//  timeline on every drag: every Take re-encrypted, every `modifiedAt` bumped, and
//  every one of them a fresh conflict candidate against a second device
//  (`ConflictResolver` decides on `modifiedAt` against the watermark). Interpolating
//  between the drop neighbours writes ONE Take instead.
//

import Foundation

public enum ManualOrder {

    /// The smallest step the arrangement ever takes when appending past either end.
    ///
    /// One millisecond — the resolution every timestamp in the model is already
    /// truncated to (`ISO8601.truncateToMilliseconds`), so it is the finest step that
    /// can still be told apart from a `createdAt`. It bounds the one race this design
    /// has: drop a card at the "now" end, and a Take created within the next
    /// millisecond lands above it rather than below. Documented rather than defended
    /// away — any scheme that reads a missing position off `createdAt` has some
    /// window, and a millisecond is the smallest one available.
    public static let step: Double = 0.001

    /// Where this Take sits on the number line: its explicit position, or its
    /// creation time when it has never been dragged.
    public static func effectiveOrder(of take: Take) -> Double {
        take.manualOrder ?? take.createdAt.timeIntervalSince1970
    }

    /// The canonical manual arrangement, OLDEST-FIRST.
    ///
    /// The `id` tie-break is not decoration: `effectiveOrder` collapses to
    /// millisecond-truncated `createdAt` for undragged Takes, so same-instant
    /// creations genuinely tie, and Swift's sort is not stable — tied rows would
    /// shuffle between reloads. Ascending on BOTH keys is the exact reverse of
    /// `DailiesViewModel.reload`'s newest-first sort, which is what makes an
    /// undragged timeline identical under either arrangement.
    public static func arranged(_ takes: [Take]) -> [Take] {
        takes.sorted {
            let a = effectiveOrder(of: $0), b = effectiveOrder(of: $1)
            if a != b { return a < b }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// The value(s) to persist so that `movingID` comes to rest at `destination` in
    /// the canonical (oldest-first) arrangement of `takes`.
    ///
    /// `destination` is an index into the list WITHOUT the moved Take — 0 puts it at
    /// the old end, `count` at the now end. Returns id → new `manualOrder` for every
    /// Take the caller must save; normally exactly one entry.
    ///
    /// Returns empty when the move is a no-op, so a drag that ends where it started
    /// writes nothing and cannot push a Take to the cloud for no reason.
    public static func reorder(_ takes: [Take],
                               moving movingID: UUID,
                               to destination: Int) -> [UUID: Double] {
        let canonical = arranged(takes)
        guard let from = canonical.firstIndex(where: { $0.id == movingID }) else { return [:] }
        let moved = canonical[from]
        var others = canonical
        others.remove(at: from)

        let index = max(0, min(destination, others.count))
        // Landed back where it started: removing at `from` and re-inserting at the
        // same index restores the original sequence, so nothing moved. Write nothing
        // — a drag that changes no order must not push a Take to the cloud.
        if index == from { return [:] }

        let below = index > 0 ? effectiveOrder(of: others[index - 1]) : nil
        let above = index < others.count ? effectiveOrder(of: others[index]) : nil

        switch (below, above) {
        case (nil, nil):
            // The only Take there is. Its position is meaningless; leave it undragged.
            return [:]
        case (nil, .some(let above)):
            return [moved.id: above - step]
        case (.some(let below), nil):
            return [moved.id: below + step]
        case (.some(let below), .some(let above)):
            let mid = below + (above - below) / 2
            // PRECISION EXHAUSTED. Halving the same gap ~50 times lands the midpoint
            // on one of its own neighbours, and from there the arrangement would stop
            // responding to drags with no visible reason. Spread everything onto fresh
            // integers instead. This is the one path that writes more than one Take,
            // and it is why the renumber exists at all rather than being the default:
            // it costs a full re-push, so it happens when it must and not before.
            if mid <= below || mid >= above {
                return renumbered(inserting: moved, into: others, at: index)
            }
            return [moved.id: mid]
        }
    }

    /// Fresh evenly-spaced values for the whole arrangement, with `moved` seated at
    /// `index`. Spacing of 1.0 from 1.0 upward — far below any epoch, so a Take
    /// created afterwards (which carries `nil`, i.e. its epoch) still sorts to the
    /// now end, and the gap leaves room for ~50 further halvings.
    private static func renumbered(inserting moved: Take,
                                   into others: [Take],
                                   at index: Int) -> [UUID: Double] {
        var sequence = others
        sequence.insert(moved, at: max(0, min(index, others.count)))
        var values: [UUID: Double] = [:]
        for (offset, take) in sequence.enumerated() {
            values[take.id] = Double(offset + 1)
        }
        return values
    }
}
