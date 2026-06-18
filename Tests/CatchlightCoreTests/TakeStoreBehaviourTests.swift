//
//  TakeStoreBehaviourTests.swift
//  CatchlightCoreTests — Task 7.2
//
//  Behaviour-level tests against the `TakeStore` protocol contract, driven by
//  the in-memory implementation. The production `EncryptedTakeStore` (iOS
//  target) must satisfy the same contract — the SHARED suite in
//  `TakeStoreContractTests.swift` now runs identical assertions against both
//  implementations; this file keeps the original behaviour-level coverage.
//
//  Each test is fully isolated: a fresh `InMemoryTakeStore` per `setUp`. No
//  shared fixture state, so tests are order-independent.
//
//  ORDER NOTE: `allTakes()` is sorted by `createdAt ASCENDING` (oldest first)
//  in both implementations — NOT "newest first" as the task spec assumes. The
//  tests below assert the actual behaviour and the work-plan note flags the
//  discrepancy for follow-up.
//

import XCTest
@testable import CatchlightCore

final class TakeStoreBehaviourTests: XCTestCase {

    private var store: InMemoryTakeStore!

    override func setUp() {
        super.setUp()
        store = InMemoryTakeStore()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - CRUD

    func testTakeStore_upsertAndFetch_roundTripsAllFields() throws {
        let take = TestFixtures.richTake()
        try store.upsert(take)
        let read = try store.take(id: take.id)
        XCTAssertEqual(read, take, "All fields must round-trip through upsert + take(id:)")
    }

    func testTakeStore_upsertSameIdTwice_replacesNotDuplicates() throws {
        let id = UUID()
        let now = Date()
        let first  = Take(id: id, createdAt: now, modifiedAt: now, blocks: [.textLine("first")])
        let second = Take(id: id, createdAt: now, modifiedAt: now, blocks: [.textLine("second")])
        try store.upsert(first)
        try store.upsert(second)
        let all = try store.allTakes()
        XCTAssertEqual(all.count, 1, "Same UUID must not produce two rows")
        XCTAssertEqual(all.first?.primaryText, "second")
    }

    func testTakeStore_upsertExisting_bumpsModifiedAtWhenCallerSetsIt() throws {
        let id = UUID()
        let created = Date(timeIntervalSinceReferenceDate: 100_000)
        var take = Take(id: id, createdAt: created, modifiedAt: created, blocks: [.textLine("v1")])
        try store.upsert(take)
        take.primaryText = "v2"
        take.modifiedAt = created.addingTimeInterval(60)
        try store.upsert(take)
        let read = try XCTUnwrap(try store.take(id: id))
        XCTAssertEqual(read.primaryText, "v2")
        XCTAssertGreaterThan(read.modifiedAt, read.createdAt)
    }

    func testTakeStore_deleteUnknownId_throwsNotFound() {
        XCTAssertThrowsError(try store.delete(id: UUID())) { error in
            guard case StorageError.notFound = error else {
                return XCTFail("Expected .notFound, got \(error)")
            }
        }
    }

    func testTakeStore_deleteRemovesRecord_andSubsequentFetchReturnsNil() throws {
        let take = Take(blocks: [.textLine("to delete")])
        try store.upsert(take)
        try store.delete(id: take.id)
        XCTAssertNil(try store.take(id: take.id))
    }

    func testTakeStore_fetchUnknownId_returnsNil() throws {
        XCTAssertNil(try store.take(id: UUID()))
    }

    // MARK: - Collection behaviour

    func testTakeStore_emptyStore_allTakesIsEmptyArray() throws {
        XCTAssertEqual(try store.allTakes(), [])
    }

    /// allTakes sort order is `createdAt ASCENDING` — locks the contract that
    /// the timeline view (newest-first) inverts itself in the view layer.
    func testTakeStore_allTakes_sortedByCreatedAtAscending() throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let mid    = Take(id: UUID(), createdAt: t0.addingTimeInterval(50), modifiedAt: t0)
        let oldest = Take(id: UUID(), createdAt: t0.addingTimeInterval(10), modifiedAt: t0)
        let newest = Take(id: UUID(), createdAt: t0.addingTimeInterval(99), modifiedAt: t0)
        try store.upsert(mid)
        try store.upsert(oldest)
        try store.upsert(newest)
        let ids = try store.allTakes().map(\.id)
        XCTAssertEqual(ids, [oldest.id, mid.id, newest.id])
    }

    func testTakeStore_largeBatch_500TakesRoundTrip() throws {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        for i in 0..<500 {
            let take = Take(
                id: UUID(),
                createdAt: base.addingTimeInterval(Double(i)),
                modifiedAt: base.addingTimeInterval(Double(i)),
                blocks: [.textLine("take-\(i)")]
            )
            try store.upsert(take)
        }
        let all = try store.allTakes()
        XCTAssertEqual(all.count, 500)
        // Spot-check first / middle / last by order (createdAt-ascending).
        XCTAssertEqual(all.first?.primaryText, "take-0")
        XCTAssertEqual(all[249].primaryText, "take-249")
        XCTAssertEqual(all.last?.primaryText, "take-499")
    }

    func testTakeStore_takesModifiedSince_returnsOnlyChangedTakes() throws {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let old = Take(id: UUID(), createdAt: base, modifiedAt: base, blocks: [.textLine("old")])
        let fresh = Take(id: UUID(),
                         createdAt: base,
                         modifiedAt: base.addingTimeInterval(100),
                         blocks: [.textLine("fresh")])
        try store.upsert(old)
        try store.upsert(fresh)
        let cutoff = base.addingTimeInterval(50)
        let changed = try store.takesModified(since: cutoff)
        XCTAssertEqual(changed.map(\.id), [fresh.id])
    }

    func testTakeStore_search_returnsCaseInsensitiveMatches() throws {
        try store.upsert(Take(blocks: [.textLine("The Quiet Hour")]))
        try store.upsert(Take(blocks: [.textLine("Loud noise")]))
        let hits = try store.search("quiet")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.primaryText, "The Quiet Hour")
    }

    func testTakeStore_search_emptyQueryReturnsEmpty() throws {
        try store.upsert(Take(blocks: [.textLine("x")]))
        XCTAssertEqual(try store.search(""), [])
    }

    // MARK: - Obie invariant — exactly one across the whole store

    func testObie_emptyStore_currentObieIsNil() throws {
        XCTAssertNil(try store.currentObie())
    }

    func testObie_setObie_marksTargetAndIsRetrievable() throws {
        let t = Take(blocks: [.textLine("the one")])
        try store.upsert(t)
        try store.setObie(id: t.id, replaceExisting: false)
        let current = try XCTUnwrap(try store.currentObie())
        XCTAssertEqual(current.id, t.id)
        XCTAssertTrue(current.isObie)
    }

    func testObie_promotingSecond_withoutReplace_throwsObieConflict() throws {
        let a = Take(blocks: [.textLine("a")]); let b = Take(blocks: [.textLine("b")])
        try store.upsert(a); try store.upsert(b)
        try store.setObie(id: a.id, replaceExisting: false)
        XCTAssertThrowsError(try store.setObie(id: b.id, replaceExisting: false)) { error in
            guard case StorageError.obieConflict(existing: let existing) = error else {
                return XCTFail("Expected .obieConflict, got \(error)")
            }
            XCTAssertEqual(existing, a.id)
        }
        // First Obie is still the Obie.
        XCTAssertEqual(try store.currentObie()?.id, a.id)
    }

    func testObie_promotingSecond_withReplace_demotesFirst() throws {
        let a = Take(blocks: [.textLine("a")]); let b = Take(blocks: [.textLine("b")])
        try store.upsert(a); try store.upsert(b)
        try store.setObie(id: a.id, replaceExisting: false)
        try store.setObie(id: b.id, replaceExisting: true)
        let current = try XCTUnwrap(try store.currentObie())
        XCTAssertEqual(current.id, b.id, "New Obie must be b")
        let oldA = try XCTUnwrap(try store.take(id: a.id))
        XCTAssertFalse(oldA.isObie, "Previous Obie must be demoted")
        // Exactly one Obie still.
        let obieCount = try store.allTakes().filter(\.isObie).count
        XCTAssertEqual(obieCount, 1)
    }

    func testObie_setObieUnknownId_throwsNotFound() {
        XCTAssertThrowsError(try store.setObie(id: UUID(), replaceExisting: true)) { error in
            guard case StorageError.notFound = error else {
                return XCTFail("Expected .notFound, got \(error)")
            }
        }
    }

    // MARK: - Important auto-flag (owner 2026-06-18): Obie ⟹ Important, sticky.

    func testObie_setObie_autoFlagsImportant() throws {
        let t = Take(blocks: [.textLine("the one")])
        XCTAssertFalse(t.isImportant, "A plain Take starts not-Important")
        try store.upsert(t)
        try store.setObie(id: t.id, replaceExisting: false)
        let current = try XCTUnwrap(try store.currentObie())
        XCTAssertTrue(current.isImportant, "Designating Obie must auto-flag Important")
    }

    func testObie_demotedTake_staysImportant_sticky() throws {
        let a = Take(blocks: [.textLine("a")]); let b = Take(blocks: [.textLine("b")])
        try store.upsert(a); try store.upsert(b)
        try store.setObie(id: a.id, replaceExisting: false)   // a → Obie + Important
        try store.setObie(id: b.id, replaceExisting: true)    // b → Obie; a demoted
        let oldA = try XCTUnwrap(try store.take(id: a.id))
        XCTAssertFalse(oldA.isObie, "a is no longer the Obie")
        XCTAssertTrue(oldA.isImportant, "Importance is STICKY — it survives losing Obie")
    }

    // MARK: - Sequences

    func testSequence_upsertAndFetch_roundTrip() throws {
        let seq = CatchlightSequence(
            name: "Weekend shoot",
            filter: SequenceFilter(text: "shoot", requireTask: true)
        )
        try store.upsert(seq)
        let read = try XCTUnwrap(try store.sequence(id: seq.id))
        XCTAssertEqual(read, seq)
    }

    /// The saved filter is the Sequence — it must round-trip exactly.
    func testSequence_savedFilterRoundTripsExactly() throws {
        let filter = SequenceFilter(text: "darkroom", requireReminder: true,
                                    requireCompleted: true, months: ["2026-05", "2026-06"])
        let seq = CatchlightSequence(name: "kept", filter: filter)
        try store.upsert(seq)
        XCTAssertEqual(try store.sequence(id: seq.id)?.filter, filter)
    }

    func testSequence_delete_removesOnlyTheFilter() throws {
        let take = Take(blocks: [.textLine("darkroom session")])
        try store.upsert(take)
        let seq = CatchlightSequence(name: "kept", filter: SequenceFilter(text: "darkroom"))
        try store.upsert(seq)
        try store.deleteSequence(id: seq.id)
        XCTAssertNil(try store.sequence(id: seq.id))
        XCTAssertNotNil(try store.take(id: take.id), "deleting a Sequence must never touch Takes")
    }

    func testSequence_deleteUnknownId_throwsNotFound() {
        XCTAssertThrowsError(try store.deleteSequence(id: UUID())) { error in
            guard case StorageError.notFound = error else {
                return XCTFail("Expected .notFound, got \(error)")
            }
        }
    }

    func testSequence_allSequences_emptyStoreReturnsEmpty() throws {
        XCTAssertEqual(try store.allSequences(), [])
    }

    // MARK: - Sync bookkeeping

    func testStore_lastSyncDate_defaultsToNil_andRoundTrips() {
        XCTAssertNil(store.lastSyncDate())
        let now = Date()
        store.setLastSyncDate(now)
        XCTAssertEqual(store.lastSyncDate(), now)
    }
}
