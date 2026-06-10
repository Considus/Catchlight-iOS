//
//  ConflictQueueTests.swift
//  CatchlightCoreTests
//
//  Verifies the iOS-side `ConflictQueue` (Task 6.15):
//    • enqueue deduplicates by Take.id — and (2026-06-10) an incoming pair for
//      an already-pending id REPLACES the pending pair,
//    • resolve(keepLocal: true) writes the local version and removes the entry,
//    • resolve(keepLocal: false) writes the remote version,
//    • skip / dismissAll drain the queue without touching the store.
//
//  The queue lives in the iOS app target, so this test is gated by
//  `#if canImport(Catchlight)` — under `swift test` on macOS the Core tests run
//  unchanged.
//

#if canImport(Catchlight)
import XCTest
@testable import CatchlightCore
@testable import Catchlight

@MainActor
final class ConflictQueueTests: XCTestCase {

    private func makePair(body: String = "local body",
                          remoteBody: String = "remote body") -> (local: Take, remote: Take) {
        let id = UUID()
        let local = Take(id: id, bodyText: body)
        let remote = Take(id: id, bodyText: remoteBody)
        return (local, remote)
    }

    func testEnqueue_deduplicatesByID() {
        let queue = ConflictQueue()
        let pair = makePair()
        queue.enqueue([pair])
        queue.enqueue([pair])   // same id — no second entry
        XCTAssertEqual(queue.pending.count, 1)
    }

    /// 2026-06-10: an incoming pair for an already-pending id REPLACES the
    /// pending pair (was: skipped) — the user must resolve against the newest
    /// snapshot, or a stale winner could be upserted over a newer row.
    func testEnqueue_sameId_replacesPendingPairWithNewestSnapshot() {
        let queue = ConflictQueue()
        let id = UUID()
        let stale = (local: Take(id: id, bodyText: "local v1"),
                     remote: Take(id: id, bodyText: "remote v1"))
        let fresh = (local: Take(id: id, bodyText: "local v2"),
                     remote: Take(id: id, bodyText: "remote v2"))

        queue.enqueue([stale])
        queue.enqueue([fresh])

        XCTAssertEqual(queue.pending.count, 1)
        XCTAssertEqual(queue.pending.first?.local.bodyText, "local v2")
        XCTAssertEqual(queue.pending.first?.remote.bodyText, "remote v2")
    }

    /// Replacement preserves the entry's position in the queue (oldest-first
    /// surfacing order is by FIRST appearance, not by latest update).
    func testEnqueue_replacement_keepsQueuePosition() {
        let queue = ConflictQueue()
        let a = makePair()
        let b = makePair()
        queue.enqueue([a, b])

        let aUpdated = (local: Take(id: a.local.id, bodyText: "a v2"),
                        remote: Take(id: a.local.id, bodyText: "a remote v2"))
        queue.enqueue([aUpdated])

        XCTAssertEqual(queue.pending.map(\.local.id), [a.local.id, b.local.id])
        XCTAssertEqual(queue.pending.first?.local.bodyText, "a v2")
    }

    func testEnqueue_appendsDistinctConflicts() {
        let queue = ConflictQueue()
        queue.enqueue([makePair(), makePair(), makePair()])
        XCTAssertEqual(queue.pending.count, 3)
    }

    func testResolve_keepLocal() throws {
        let store = InMemoryTakeStore()
        let queue = ConflictQueue()
        let pair = makePair(body: "MINE", remoteBody: "THEIRS")
        queue.enqueue([pair])

        try queue.resolve(id: pair.local.id, keepLocal: true, store: store)

        XCTAssertTrue(queue.pending.isEmpty)
        let saved = try XCTUnwrap(try store.allTakes().first { $0.id == pair.local.id })
        XCTAssertEqual(saved.bodyText, "MINE")
    }

    func testResolve_keepRemote() throws {
        let store = InMemoryTakeStore()
        let queue = ConflictQueue()
        let pair = makePair(body: "MINE", remoteBody: "THEIRS")
        queue.enqueue([pair])

        try queue.resolve(id: pair.local.id, keepLocal: false, store: store)

        XCTAssertTrue(queue.pending.isEmpty)
        let saved = try XCTUnwrap(try store.allTakes().first { $0.id == pair.local.id })
        XCTAssertEqual(saved.bodyText, "THEIRS")
    }

    func testSkip_removesFromQueueWithoutWriting() throws {
        let store = InMemoryTakeStore()
        let queue = ConflictQueue()
        let pair = makePair()
        queue.enqueue([pair])

        queue.skip(id: pair.local.id)

        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertTrue(try store.allTakes().isEmpty,
                      "Skipping must not write either version to the store")
    }

    func testDismissAll_emptiesQueueAndLeavesStoreUntouched() throws {
        let store = InMemoryTakeStore()
        let queue = ConflictQueue()
        queue.enqueue([makePair(), makePair(), makePair()])
        XCTAssertEqual(queue.pending.count, 3)

        queue.dismissAll()

        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertTrue(try store.allTakes().isEmpty)
    }

    func testResolve_unknownIdIsNoOp() throws {
        let store = InMemoryTakeStore()
        let queue = ConflictQueue()
        // Resolving an id that was never queued should not throw or write.
        try queue.resolve(id: UUID(), keepLocal: true, store: store)
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertTrue(try store.allTakes().isEmpty)
    }
}
#endif
