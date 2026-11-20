//
//  LostEditOnLockTests.swift
//  CatchlightAppTests
//
//  ISSUE-292: the phone locks while a Take is being edited and the save that relock() makes
//  first is refused (a full disk, say). The draft lives in the editor, which the lock tears
//  down, so after the unlock the typing is nowhere. This test fails on main by design: it
//  proves the issue before a fix is chosen. Any fix that brings the typing back after the
//  unlock, into the store or handed back to an editor, makes it pass.
//

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
    func syncRecord(id: UUID) throws -> SyncRecord? { try base.syncRecord(id: id) }
    func setSyncRecord(_ record: SyncRecord?, id: UUID) throws { try base.setSyncRecord(record, id: id) }
    func applyRemote(_ take: Take) throws -> Bool { try base.applyRemote(take) }
    func release(id: UUID, ifNotModifiedAfter cutoff: Date) throws -> Bool { try base.release(id: id, ifNotModifiedAfter: cutoff) }
    func tombstones() throws -> [Tombstone] { try base.tombstones() }
    func purgeTombstones(ids: [UUID]) throws { try base.purgeTombstones(ids: ids) }
}

@MainActor
final class LostEditOnLockTests: XCTestCase {

    private var conflictDirectory: URL!

    override func setUp() {
        super.setUp()
        conflictDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LostEditOnLockTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: conflictDirectory)
        super.tearDown()
    }

    func testAnEditWhoseSaveFailsAtTheLock_isThereAfterTheUnlock() async throws {
        let store = RefusingStore()
        let stored = Take(blocks: [.textLine("Written before the lock")])
        try store.upsert(stored)
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

        // The editor is open on the Take, as DailiesView and StoryboardView register it: the
        // relock commits it through the same AppModel.commitEditedTake.
        var draft = stored
        draft.blocks = [.textLine("Typed, not saved")]
        var commit: AppModel.EditCommit?
        app.ui.commitInlineEdit = { commit = app.commitEditedTake(draft) }

        store.refuseWrites = true
        app.relock()
        XCTAssertEqual(app.lockState, .locked)
        XCTAssertEqual(commit, .failed, "the save at the lock was not refused, so the test proves nothing")
        XCTAssertEqual(try store.base.allTakes().map(\.plainText), ["Written before the lock"],
                       "the typing reached the store, so the test proves nothing")

        store.refuseWrites = false
        await app.attemptUnlock()
        XCTAssertEqual(app.lockState, .unlocked)

        let reachable = (try store.allTakes().map(\.plainText)) + [app.ui.pendingInlineNewTake?.plainText].compactMap { $0 }
        XCTAssertTrue(reachable.contains("Typed, not saved"),
                      "the typing is gone after the unlock (ISSUE-292); the app has \(reachable)")
    }
}
