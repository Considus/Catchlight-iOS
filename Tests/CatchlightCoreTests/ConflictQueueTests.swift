//
//  ConflictQueueTests.swift
//  CatchlightCoreTests
//
//  Verifies the iOS-side `ConflictQueue` (Task 6.15):
//    • enqueue deduplicates by Take.id,
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
        queue.enqueue([pair])   // same id — should be ignored
        XCTAssertEqual(queue.pending.count, 1)
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
