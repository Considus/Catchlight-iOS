//
//  ExpandedTakesTests.swift
//  CatchlightAppTests — "Expand Take" (owner 2026-08-11, D-194)
//
//  The per-Take override of the Settings "Preview" length is stored device-local as a
//  comma-joined UUID string in UserDefaults (`@AppStorage` carries String, not Set<UUID>).
//  These cover the pure parse/toggle/prune helpers, which is where the string encoding could
//  quietly go wrong — the views are a thin read over them.
//
//  iOS-only — gated on `canImport(Catchlight)`.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight
@testable import CatchlightCore

final class ExpandedTakesTests: XCTestCase {

    private typealias Store = SettingsViewModel.ExpandedTakes

    private let a = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let b = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let c = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    // MARK: - Round trip

    func testRoundTrip_preservesIDs() {
        let raw = Store.raw(from: [a, b])
        XCTAssertEqual(Store.ids(from: raw), [a, b])
    }

    func testRaw_isStableRegardlessOfSetOrder() {
        // An unordered Set would otherwise rewrite the defaults entry — and republish to
        // every observing view — on no real change.
        XCTAssertEqual(Store.raw(from: [a, b, c]), Store.raw(from: [c, a, b]))
    }

    func testIDs_emptyString_isEmpty() {
        XCTAssertTrue(Store.ids(from: "").isEmpty)
    }

    /// A corrupted value must degrade to "nothing expanded", never break the timeline.
    func testIDs_ignoresJunkEntries() {
        let raw = "\(a.uuidString),not-a-uuid,,\(b.uuidString)"
        XCTAssertEqual(Store.ids(from: raw), [a, b])
    }

    // MARK: - Toggle

    func testToggling_addsThenRemoves() {
        let added = Store.toggling(a, in: "")
        XCTAssertTrue(Store.contains(a, in: added))

        let removed = Store.toggling(a, in: added)
        XCTAssertFalse(Store.contains(a, in: removed))
        XCTAssertTrue(Store.ids(from: removed).isEmpty)
    }

    func testToggling_leavesOtherIDsAlone() {
        let raw = Store.raw(from: [a, b])
        let toggled = Store.toggling(a, in: raw)
        XCTAssertEqual(Store.ids(from: toggled), [b])
    }

    // MARK: - Prune

    func testPruned_dropsIDsForDeletedTakes() {
        let raw = Store.raw(from: [a, b, c])
        let pruned = Store.pruned(raw, keeping: [a, c])
        XCTAssertEqual(pruned.map(Store.ids(from:)), [a, c])
    }

    /// nil when nothing changed, so the caller can skip the write. This runs on every
    /// timeline reload — writing unconditionally would churn the defaults and thrash the
    /// views observing that key.
    func testPruned_returnsNilWhenNothingChanged() {
        let raw = Store.raw(from: [a, b])
        XCTAssertNil(Store.pruned(raw, keeping: [a, b, c]))
    }

    func testPruned_allGone_returnsEmptyString() {
        let raw = Store.raw(from: [a, b])
        XCTAssertEqual(Store.pruned(raw, keeping: []), "")
    }
}
#endif
