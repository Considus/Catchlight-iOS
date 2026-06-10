//
//  TakeStoreContractTests.swift
//  CatchlightCoreTests — 2026-06-10 remediation, shared store contract suite
//
//  ONE set of assertions for the full `TakeStore` protocol contract, run against
//  EVERY implementation. The base class drives `InMemoryTakeStore` (always runs,
//  including under `swift test` on macOS); `EncryptedTakeStoreContractTests`
//  (see EncryptedTakeStoreTests.swift, iOS-gated) subclasses it to run the SAME
//  tests against the production SQLite store in a temp directory.
//
//  This closes the long-standing gap where `takesModified(since:)`, `search`,
//  `lastSyncDate`, and the tombstone API had NO coverage on the production
//  store — the two implementations are contract-identical by design, so they
//  must be proven against identical assertions.
//
//  Subclassing pattern: XCTest runs inherited test methods against the
//  subclass's `makeStore()` override. Tests use only the `TakeStore` protocol
//  surface, so they cannot accidentally depend on implementation details.
//

import XCTest
import CryptoKit
@testable import CatchlightCore

class TakeStoreContractTests: XCTestCase {

    /// Factory the contract runs against. Subclasses override.
    func makeStore() throws -> TakeStore { InMemoryTakeStore() }

    private(set) var store: TakeStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = try makeStore()
    }

    override func tearDownWithError() throws {
        store = nil
        try super.tearDownWithError()
    }

    // MARK: - Upsert / fetch round-trip

    func testContract_upsertAndFetch_roundTripsAllFields() throws {
        let take = TestFixtures.richTake()
        try store.upsert(take)
        XCTAssertEqual(try store.take(id: take.id), take)
    }

    func testContract_fetchUnknownId_returnsNil() throws {
        XCTAssertNil(try store.take(id: UUID()))
    }

    func testContract_upsertSameIdTwice_replacesNotDuplicates() throws {
        let id = UUID()
        let t0 = ISO8601.date(from: "2026-05-01T09:00:00.000Z")!
        try store.upsert(Take(id: id, createdAt: t0, modifiedAt: t0, bodyText: "v1"))
        try store.upsert(Take(id: id, createdAt: t0, modifiedAt: t0, bodyText: "v2"))
        let all = try store.allTakes()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.bodyText, "v2")
    }

    // MARK: - Delete + tombstones (2026-06-10 deletion propagation)

    func testContract_deleteRemovesRecord_andFetchReturnsNil() throws {
        let take = TestFixtures.richTake()
        try store.upsert(take)
        try store.delete(id: take.id)
        XCTAssertNil(try store.take(id: take.id))
    }

    func testContract_deleteUnknownId_throwsNotFound() {
        XCTAssertThrowsError(try store.delete(id: UUID())) { error in
            guard case StorageError.notFound = error else {
                return XCTFail("Expected .notFound, got \(error)")
            }
        }
    }

    func testContract_deleteRecordsTombstone() throws {
        let take = TestFixtures.richTake()
        try store.upsert(take)
        XCTAssertTrue(try store.tombstones().isEmpty)

        try store.delete(id: take.id)
        let tombstones = try store.tombstones()
        XCTAssertEqual(tombstones.map(\.id), [take.id])
        XCTAssertLessThanOrEqual(abs(tombstones[0].deletedAt.timeIntervalSinceNow), 60,
                                 "deletedAt is stamped at deletion time")
    }

    func testContract_purgeTombstones_removesOnlyRequestedIds() throws {
        let a = TestFixtures.richTake(id: UUID())
        let b = TestFixtures.richTake(id: UUID())
        try store.upsert(a)
        try store.upsert(b)
        try store.delete(id: a.id)
        try store.delete(id: b.id)

        try store.purgeTombstones(ids: [a.id])
        XCTAssertEqual(try store.tombstones().map(\.id), [b.id])

        try store.purgeTombstones(ids: [b.id])
        XCTAssertTrue(try store.tombstones().isEmpty)
    }

    func testContract_upsertClearsPendingTombstoneForSameId() throws {
        let take = TestFixtures.richTake()
        try store.upsert(take)
        try store.delete(id: take.id)
        XCTAssertFalse(try store.tombstones().isEmpty)

        try store.upsert(take)   // re-creation supersedes the deletion record
        XCTAssertTrue(try store.tombstones().isEmpty)
        XCTAssertNotNil(try store.take(id: take.id))
    }

    // MARK: - Collection ordering

    func testContract_allTakes_emptyStoreReturnsEmpty() throws {
        XCTAssertEqual(try store.allTakes(), [])
    }

    func testContract_allTakes_sortedByCreatedAtAscending() throws {
        let t0 = ISO8601.date(from: "2026-05-01T09:00:00.000Z")!
        let mid    = Take(id: UUID(), createdAt: t0.addingTimeInterval(50), modifiedAt: t0)
        let oldest = Take(id: UUID(), createdAt: t0.addingTimeInterval(10), modifiedAt: t0)
        let newest = Take(id: UUID(), createdAt: t0.addingTimeInterval(99), modifiedAt: t0)
        try store.upsert(mid)
        try store.upsert(oldest)
        try store.upsert(newest)
        XCTAssertEqual(try store.allTakes().map(\.id), [oldest.id, mid.id, newest.id])
    }

    // MARK: - takesModified(since:) — strict `>` semantics

    func testContract_takesModifiedSince_strictlyAfterOnly() throws {
        let base = ISO8601.date(from: "2026-05-01T09:00:00.000Z")!
        let atCutoff = Take(id: UUID(), createdAt: base, modifiedAt: base, bodyText: "at")
        let after = Take(id: UUID(), createdAt: base,
                         modifiedAt: base.addingTimeInterval(0.001), bodyText: "after")
        try store.upsert(atCutoff)
        try store.upsert(after)

        // Cutoff EXACTLY equal to a Take's modifiedAt → excluded (strict >).
        let changed = try store.takesModified(since: base)
        XCTAssertEqual(changed.map(\.id), [after.id],
                       "modifiedAt == cutoff must be excluded; strictly-after included")
    }

    func testContract_takesModifiedSinceNil_returnsAll() throws {
        try store.upsert(TestFixtures.richTake(id: UUID()))
        try store.upsert(TestFixtures.richTake(id: UUID()))
        XCTAssertEqual(try store.takesModified(since: nil).count, 2)
    }

    // MARK: - Search — case-insensitive substring

    func testContract_search_caseInsensitiveSubstring() throws {
        let t0 = ISO8601.date(from: "2026-05-01T09:00:00.000Z")!
        try store.upsert(Take(createdAt: t0, modifiedAt: t0, bodyText: "The Quiet Hour"))
        try store.upsert(Take(createdAt: t0.addingTimeInterval(1), modifiedAt: t0, bodyText: "Loud noise"))
        let hits = try store.search("qUiEt")
        XCTAssertEqual(hits.map(\.bodyText), ["The Quiet Hour"])
    }

    func testContract_search_emptyQueryReturnsEmpty() throws {
        try store.upsert(Take(bodyText: "anything"))
        XCTAssertEqual(try store.search(""), [])
    }

    func testContract_search_noMatchReturnsEmpty() throws {
        try store.upsert(Take(bodyText: "alpha"))
        XCTAssertEqual(try store.search("zebra"), [])
    }

    // MARK: - Sequences

    func testContract_sequence_roundTripPreservesOrder() throws {
        let ids = (0..<10).map { _ in UUID() }
        let t0 = ISO8601.date(from: "2026-05-01T09:00:00.000Z")!
        let seq = CatchlightSequence(name: "Weekend shoot", createdAt: t0, modifiedAt: t0, takeIds: ids)
        try store.upsert(seq)
        let read = try XCTUnwrap(try store.sequence(id: seq.id))
        XCTAssertEqual(read, seq)
        XCTAssertEqual(read.takeIds, ids, "narrative order must round-trip exactly")
    }

    func testContract_allSequences_emptyStoreReturnsEmpty() throws {
        XCTAssertEqual(try store.allSequences(), [])
    }

    // MARK: - Single-Obie invariant

    func testContract_obie_emptyStoreIsNil() throws {
        XCTAssertNil(try store.currentObie())
    }

    func testContract_obie_secondWithoutReplace_throwsObieConflict() throws {
        let a = Take(bodyText: "a"); let b = Take(bodyText: "b")
        try store.upsert(a); try store.upsert(b)
        try store.setObie(id: a.id, replaceExisting: false)
        XCTAssertThrowsError(try store.setObie(id: b.id, replaceExisting: false)) { error in
            guard case StorageError.obieConflict(existing: let existing) = error else {
                return XCTFail("Expected .obieConflict, got \(error)")
            }
            XCTAssertEqual(existing, a.id)
        }
        XCTAssertEqual(try store.currentObie()?.id, a.id, "first Obie must be untouched")
    }

    func testContract_obie_replaceExisting_demotesFirst_exactlyOneObie() throws {
        let a = Take(bodyText: "a"); let b = Take(bodyText: "b")
        try store.upsert(a); try store.upsert(b)
        try store.setObie(id: a.id, replaceExisting: false)
        try store.setObie(id: b.id, replaceExisting: true)

        XCTAssertEqual(try store.currentObie()?.id, b.id)
        XCTAssertFalse(try XCTUnwrap(try store.take(id: a.id)).isObie)
        XCTAssertEqual(try store.allTakes().filter(\.isObie).count, 1)
    }

    func testContract_obie_unknownId_throwsNotFound() {
        XCTAssertThrowsError(try store.setObie(id: UUID(), replaceExisting: true)) { error in
            guard case StorageError.notFound = error else {
                return XCTFail("Expected .notFound, got \(error)")
            }
        }
    }

    // MARK: - Sync bookkeeping

    func testContract_lastSyncDate_defaultsToNil_andRoundTrips() throws {
        XCTAssertNil(store.lastSyncDate())
        // ms-aligned: the production store persists via the ISO-8601 ms wire format.
        let stamp = ISO8601.truncateToMilliseconds(Date())
        store.setLastSyncDate(stamp)
        XCTAssertEqual(store.lastSyncDate(), stamp)
    }
}
