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
        try store.upsert(Take(id: id, createdAt: t0, modifiedAt: t0, blocks: [.textLine("v1")]))
        try store.upsert(Take(id: id, createdAt: t0, modifiedAt: t0, blocks: [.textLine("v2")]))
        let all = try store.allTakes()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.primaryText, "v2")
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

    // MARK: - applyRemote — the sync-apply path (delete-resurrection guard)

    func testContract_applyRemote_liveTombstoneWins_nothingWritten() throws {
        var take = TestFixtures.richTake()
        try store.upsert(take)
        try store.delete(id: take.id)
        let deletedAt = try XCTUnwrap(store.tombstones().first).deletedAt

        // Remote copy NOT edited after the deletion (ties included) → blocked.
        take.modifiedAt = deletedAt
        XCTAssertFalse(try store.applyRemote(take))
        XCTAssertNil(try store.take(id: take.id), "blocked apply must not resurrect")
        XCTAssertEqual(try store.tombstones().map(\.id), [take.id],
                       "blocked apply must not clear the pending tombstone")
    }

    func testContract_applyRemote_remoteEditedAfterDeletion_resurrects() throws {
        var take = TestFixtures.richTake()
        try store.upsert(take)
        try store.delete(id: take.id)
        let deletedAt = try XCTUnwrap(store.tombstones().first).deletedAt

        // Edit-wins: a remote edit STRICTLY after the deletion re-creates the
        // Take and supersedes the deletion record, exactly like upsert.
        take.modifiedAt = deletedAt.addingTimeInterval(1)
        XCTAssertTrue(try store.applyRemote(take))
        XCTAssertNotNil(try store.take(id: take.id))
        XCTAssertTrue(try store.tombstones().isEmpty)
    }

    func testContract_applyRemote_noTombstone_behavesLikeUpsert() throws {
        let take = TestFixtures.richTake()
        XCTAssertTrue(try store.applyRemote(take))
        XCTAssertEqual(try store.take(id: take.id)?.id, take.id)
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
        let atCutoff = Take(id: UUID(), createdAt: base, modifiedAt: base, blocks: [.textLine("at")])
        let after = Take(id: UUID(), createdAt: base,
                         modifiedAt: base.addingTimeInterval(0.001), blocks: [.textLine("after")])
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
        try store.upsert(Take(createdAt: t0, modifiedAt: t0, blocks: [.textLine("The Quiet Hour")]))
        try store.upsert(Take(createdAt: t0.addingTimeInterval(1), modifiedAt: t0, blocks: [.textLine("Loud noise")]))
        let hits = try store.search("qUiEt")
        XCTAssertEqual(hits.map(\.primaryText), ["The Quiet Hour"])
    }

    func testContract_search_emptyQueryReturnsEmpty() throws {
        try store.upsert(Take(blocks: [.textLine("anything")]))
        XCTAssertEqual(try store.search(""), [])
    }

    func testContract_search_noMatchReturnsEmpty() throws {
        try store.upsert(Take(blocks: [.textLine("alpha")]))
        XCTAssertEqual(try store.search("zebra"), [])
    }

    // MARK: - Sequences

    func testContract_sequence_roundTripPreservesFilter() throws {
        let t0 = ISO8601.date(from: "2026-05-01T09:00:00.000Z")!
        let filter = SequenceFilter(text: "shoot", requireTask: true, months: ["2026-05"])
        let seq = CatchlightSequence(name: "Weekend shoot", createdAt: t0, modifiedAt: t0, filter: filter)
        try store.upsert(seq)
        let read = try XCTUnwrap(try store.sequence(id: seq.id))
        XCTAssertEqual(read, seq)
        XCTAssertEqual(read.filter, filter, "the saved filter IS the Sequence — must round-trip exactly")
    }

    func testContract_deleteSequence_removesDefinitionOnly() throws {
        let take = Take(blocks: [.textLine("darkroom session")])
        try store.upsert(take)
        let seq = CatchlightSequence(name: "kept", filter: SequenceFilter(text: "darkroom"))
        try store.upsert(seq)
        try store.deleteSequence(id: seq.id)
        XCTAssertNil(try store.sequence(id: seq.id))
        XCTAssertNotNil(try store.take(id: take.id))
        XCTAssertThrowsError(try store.deleteSequence(id: seq.id)) { error in
            guard case StorageError.notFound = error else {
                return XCTFail("Expected .notFound, got \(error)")
            }
        }
    }

    func testContract_allSequences_emptyStoreReturnsEmpty() throws {
        XCTAssertEqual(try store.allSequences(), [])
    }

    // MARK: - Single-Obie invariant

    func testContract_obie_emptyStoreIsNil() throws {
        XCTAssertNil(try store.currentObie())
    }

    func testContract_obie_secondWithoutReplace_throwsObieConflict() throws {
        let a = Take(blocks: [.textLine("a")]); let b = Take(blocks: [.textLine("b")])
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
        let a = Take(blocks: [.textLine("a")]); let b = Take(blocks: [.textLine("b")])
        try store.upsert(a); try store.upsert(b)
        try store.setObie(id: a.id, replaceExisting: false)
        try store.setObie(id: b.id, replaceExisting: true)

        XCTAssertEqual(try store.currentObie()?.id, b.id)
        XCTAssertFalse(try XCTUnwrap(try store.take(id: a.id)).isObie)
        XCTAssertEqual(try store.allTakes().filter(\.isObie).count, 1)
    }

    /// The inline editor (Iris / Focus-ring) and "Obie this" capture persist an
    /// Obie by UPSERTING a Take with isObie = true (vm.save → store.upsert), NOT via
    /// setObie. Both implementations claim upsert enforces the single-Obie invariant.
    /// Repro for owner-reported 2026-06-23: a second Obie set via the Iris persisted
    /// ALONGSIDE the first (two Obies — the new one invisible, excluded from the
    /// timeline rows and not the pinned Obie).
    func testContract_obie_upsertSecondObie_demotesFirst_exactlyOneObie() throws {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let a = Take(id: UUID(), createdAt: t0, modifiedAt: t0,
                     blocks: [.textLine("a")], isObie: true)
        let b = Take(id: UUID(), createdAt: t0.addingTimeInterval(1),
                     modifiedAt: t0.addingTimeInterval(1),
                     blocks: [.textLine("b")], isObie: true)
        try store.upsert(a)
        try store.upsert(b)

        XCTAssertEqual(try store.allTakes().filter(\.isObie).count, 1,
                       "Upserting a second Obie must demote the first — exactly one Obie")
        XCTAssertEqual(try store.currentObie()?.id, b.id,
                       "The most recently upserted Obie must be the current one")
        XCTAssertFalse(try XCTUnwrap(try store.take(id: a.id)).isObie,
                       "The first Obie must be demoted")
    }

    /// The upsert-path demotion must BUMP the demoted Take's `modifiedAt`
    /// (2026-07-01): `pushOutbound` selects by `modifiedAt > watermark`, so an
    /// un-bumped demotion never re-uploaded — the cloud kept a second
    /// isObie=true blob and every later pull surfaced a phantom conflict via
    /// ConflictResolver's (false, false) branch. Matches `setObie`, which has
    /// always bumped both sides. The bump must also be ms-truncated (the known
    /// sub-millisecond phantom-conflict class, PR #79).
    func testContract_obie_upsertDemotion_bumpsDemotedModifiedAt() throws {
        let t0 = ISO8601.date(from: "2026-05-01T09:00:00.000Z")!
        let a = Take(id: UUID(), createdAt: t0, modifiedAt: t0,
                     blocks: [.textLine("a")], isObie: true)
        let b = Take(id: UUID(), createdAt: t0.addingTimeInterval(1),
                     modifiedAt: t0.addingTimeInterval(1),
                     blocks: [.textLine("b")], isObie: true)
        try store.upsert(a)
        try store.upsert(b)

        let demoted = try XCTUnwrap(try store.take(id: a.id))
        XCTAssertFalse(demoted.isObie)
        XCTAssertGreaterThan(demoted.modifiedAt, t0,
                             "demotion must bump modifiedAt so the demotion syncs")
        XCTAssertEqual(demoted.modifiedAt,
                       ISO8601.truncateToMilliseconds(demoted.modifiedAt),
                       "the bumped timestamp must be ms-normalised")
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
