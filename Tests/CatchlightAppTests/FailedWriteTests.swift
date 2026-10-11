//
//  FailedWriteTests.swift
//  CatchlightAppTests
//
//  A write or read the store refuses must never cost the user what they typed or
//  hand them an export they would trust as a backup. Two paths used to:
//  - an in-place edit whose save failed closed the editor and dropped the draft;
//  - an export whose read failed shared an empty file, including on the way to
//    Start over, where the footer calls exporting "the only way back".
//
//  iOS-only — gated on `canImport(Catchlight)`.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight
@testable import CatchlightCore

/// Forwards to an `InMemoryTakeStore`, failing Take writes or reads on cue.
private final class RefusingStore: TakeStore {
    let base = InMemoryTakeStore()
    var refuseWrites = false
    var refuseReads = false
    struct Refused: Error {}
    func upsert(_ take: Take) throws {
        if refuseWrites { throw Refused() }
        try base.upsert(take)
    }
    func allTakes() throws -> [Take] {
        if refuseReads { throw Refused() }
        return try base.allTakes()
    }
    func delete(id: UUID) throws { try base.delete(id: id) }
    func take(id: UUID) throws -> Take? { try base.take(id: id) }
    func takesModified(since date: Date?) throws -> [Take] { try base.takesModified(since: date) }
    func search(_ query: String) throws -> [Take] { try base.search(query) }
    func upsert(_ sequence: CatchlightSequence) throws { try base.upsert(sequence) }
    func sequence(id: UUID) throws -> CatchlightSequence? { try base.sequence(id: id) }
    func allSequences() throws -> [CatchlightSequence] { try base.allSequences() }
    func deleteSequence(id: UUID) throws { try base.deleteSequence(id: id) }
    func currentObie() throws -> Take? { try base.currentObie() }
    func setObie(id: UUID, replaceExisting: Bool) throws { try base.setObie(id: id, replaceExisting: replaceExisting) }
    func lastSyncDate() -> Date? { base.lastSyncDate() }
    func setLastSyncDate(_ date: Date) { base.setLastSyncDate(date) }
    func applyRemote(_ take: Take) throws -> Bool { try base.applyRemote(take) }
    func release(id: UUID, ifNotModifiedAfter cutoff: Date) throws -> Bool { try base.release(id: id, ifNotModifiedAfter: cutoff) }
    func tombstones() throws -> [Tombstone] { try base.tombstones() }
    func purgeTombstones(ids: [UUID]) throws { try base.purgeTombstones(ids: ids) }
}

@MainActor
final class FailedWriteTests: XCTestCase {

    private var conflictDirectory: URL!

    override func setUp() {
        super.setUp()
        conflictDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FailedWriteTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: conflictDirectory)
        super.tearDown()
    }

    /// An unlocked, onboarded, entitled AppModel over `store`, its conflict queue kept in
    /// this test's directory.
    private func makeUnlocked(_ store: RefusingStore) async -> AppModel {
        let subscription = SubscriptionManager()
        subscription.forceStatusForTesting(.subscribed)
        let app = AppModel(
            needsOnboarding: false,
            initialStore: InMemoryTakeStore(),
            session: SessionController(),
            makeStoreFromKeys: { _ in store },
            unlockKeys: { KeyHierarchy(masterKeyBytes: Data(repeating: 7, count: 32)) },
            lockState: .locked,
            subscription: subscription,
            conflictDirectory: conflictDirectory
        )
        await app.attemptUnlock()
        XCTAssertEqual(app.lockState, .unlocked)
        return app
    }

    // MARK: - Saving an in-place edit

    func testCommitEditedTake_refusedWrite_reportsFailed_andLeavesTheStoredTakeAlone() async throws {
        let store = RefusingStore()
        let stored = Take(blocks: [.textLine("before the edit")])
        try store.upsert(stored)
        let app = await makeUnlocked(store)
        var draft = stored
        draft.blocks = [.textLine("typed, then the save failed")]

        store.refuseWrites = true
        XCTAssertEqual(app.commitEditedTake(draft), .failed,
                       "a refused write must not be reported as saved, or the editor closes on the typing")
        XCTAssertEqual(try store.take(id: stored.id)?.plainText, "before the edit")
        XCTAssertEqual(app.dailiesVM.lastError, "Couldn't save that Take.")
    }

    func testCommitEditedTake_writeAccepted_isSaved() async throws {
        let store = RefusingStore()
        let app = await makeUnlocked(store)
        let draft = Take(blocks: [.textLine("an ordinary edit")])

        XCTAssertEqual(app.commitEditedTake(draft), .saved)
        XCTAssertEqual(try store.allTakes().map(\.plainText), ["an ordinary edit"])
    }

    /// The editor was open when a conflict arrived for its Take, so the edit is kept as a new
    /// Take. If that write is refused too, the editor must stay open on the typing, and the
    /// strip must not claim the edit was kept.
    func testCommitEditedTake_onAHeldTake_refusedCopy_reportsFailed() async throws {
        let store = RefusingStore()
        let stored = Take(blocks: [.textLine("original")])
        try store.upsert(stored)
        let app = await makeUnlocked(store)
        app.conflictQueue.enqueue([(local: stored, remote: Take(id: stored.id, blocks: [.textLine("from the other device")]))])
        var draft = stored
        draft.blocks = [.textLine("typed before the conflict arrived")]

        store.refuseWrites = true
        XCTAssertEqual(app.commitEditedTake(draft), .failed)
        XCTAssertEqual(try store.allTakes().map(\.plainText), ["original"])
        XCTAssertEqual(app.dailiesVM.lastError, "Couldn't save that Take.")
    }

    // MARK: - Reading the Takes for an export

    func testTakesForExport_unreadableStore_givesNothingToExport_andSaysSo() async throws {
        let store = RefusingStore()
        try store.upsert(Take(blocks: [.textLine("a Take the user means to keep")]))
        let app = await makeUnlocked(store)

        store.refuseReads = true
        XCTAssertNil(app.dailiesVM.takesForExport(),
                     "an unreadable store must not become an empty export the user trusts as a backup")
        XCTAssertEqual(app.dailiesVM.lastError,
                       "Your Takes couldn't be read, so nothing was exported. Don't start over until an export works.")
    }

    func testTakesForExport_readableStore_givesEveryTake() async throws {
        let store = RefusingStore()
        try store.upsert(Take(createdAt: Date(timeIntervalSince1970: 1), blocks: [.textLine("first")]))
        try store.upsert(Take(createdAt: Date(timeIntervalSince1970: 2), blocks: [.textLine("second")]))
        let app = await makeUnlocked(store)

        XCTAssertEqual(app.dailiesVM.takesForExport()?.map(\.plainText), ["first", "second"])
        XCTAssertNil(app.dailiesVM.lastError)
    }
}
#endif
