//
//  LostEditOnLockTests.swift
//  CatchlightAppTests
//
//  The phone locks while a Take is being edited and the save that relock() makes
//  first is refused (a full disk, say). The draft lives in the editor, which the lock tears
//  down. The fix (owner 2026-11-20, "Hold it, give it back"): the edit is sealed and held in
//  memory across the lock, saved again quietly after the unlock, and handed back to the editor
//  only if that save fails too. Quitting wipes it.
//

import SwiftUI
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

    private let typed = "Typed, not saved"

    /// An unlocked app over `store` holding "Written before the lock", with the editor open on it
    /// (as DailiesView and StoryboardView register it: the relock commits through the same
    /// `AppModel.commitEditedTake`), then a relock whose save of the typing is refused.
    private func lockWithARefusedEdit(_ store: RefusingStore, backgroundedFirst: Bool = false) async throws -> AppModel {
        let stored = Take(blocks: [.textLine("Written before the lock")])
        try store.upsert(stored)
        let subscription = SubscriptionManager()
        subscription.forceStatusForTesting(.subscribed)
        let session = SessionController()
        let app = AppModel(
            needsOnboarding: false,
            initialStore: InMemoryTakeStore(),
            session: session,
            makeStoreFromKeys: { _ in store },
            unlockKeys: { KeyHierarchy(masterKeyBytes: Data(repeating: 7, count: 32)) },
            lockState: .locked,
            subscription: subscription,
            conflictDirectory: conflictDirectory
        )
        await app.attemptUnlock()
        XCTAssertEqual(app.lockState, .unlocked)

        var draft = stored
        draft.blocks = [.textLine(typed)]
        var commit: AppModel.EditCommit?
        app.ui.commitInlineEdit = { commit = app.commitEditedTake(draft) }

        // A trip to the background drops the session's derived keys while the app stays unlocked.
        if backgroundedFirst { session.handleScenePhase(.background) }
        store.refuseWrites = true
        app.relock()
        XCTAssertEqual(app.lockState, .locked)
        XCTAssertEqual(commit, .failed, "the save at the lock was not refused, so the test proves nothing")
        XCTAssertEqual(try store.base.allTakes().map(\.plainText), ["Written before the lock"],
                       "the typing reached the store, so the test proves nothing")
        return app
    }

    /// Owner, 2026-11-20: "Hold it, give it back", and "Save quietly if it works".
    func testAnEditWhoseSaveFailsAtTheLock_isThereAfterTheUnlock() async throws {
        let store = RefusingStore()
        let app = try await lockWithARefusedEdit(store)
        XCTAssertTrue(app.hasHeldEdit, "the refused edit is not held across the lock")

        store.refuseWrites = false
        await app.attemptUnlock()
        XCTAssertEqual(app.lockState, .unlocked)

        XCTAssertEqual(try store.allTakes().map(\.plainText), [typed], "the typing was not saved again after the unlock")
        XCTAssertNil(app.ui.pendingInlineNewTake, "a save that worked hands nothing back")
        XCTAssertFalse(app.hasHeldEdit, "what was held is wiped once given back")
    }

    /// While locked, what is held is sealed: the typing isn't in its bytes.
    func testWhileLocked_theHeldEditIsSealed() async throws {
        let app = try await lockWithARefusedEdit(RefusingStore())
        let sealed = try XCTUnwrap(app.heldEdit?.sealed)
        XCTAssertNil(sealed.range(of: Data(typed.utf8)), "the held edit is readable")
    }

    /// The save after the unlock is refused too: the typing goes back to the editor with the
    /// save notice, and nothing is held any more.
    func testAHeldEditWhoseSaveIsRefusedAgain_goesBackToTheEditor() async throws {
        let store = RefusingStore()
        let app = try await lockWithARefusedEdit(store)
        app.ui.isStoryboardPresented = true

        await app.attemptUnlock()

        XCTAssertEqual(app.ui.pendingInlineNewTake?.plainText, typed, "the typing was not handed back")
        XCTAssertFalse(app.ui.isStoryboardPresented, "the editor must not sit hidden under the Storyboard")
        XCTAssertEqual(app.dailiesVM.lastError, "Couldn't save that Take.")
        XCTAssertFalse(app.hasHeldEdit)
        XCTAssertEqual(try store.base.allTakes().map(\.plainText), ["Written before the lock"])
    }

    /// Quitting wipes what is held: it is kept in memory only.
    func testQuitting_wipesTheHeldEdit() async throws {
        let app = try await lockWithARefusedEdit(RefusingStore())
        NotificationCenter.default.post(name: UIApplication.willTerminateNotification, object: nil)
        XCTAssertFalse(app.hasHeldEdit, "quitting did not wipe the held edit")
    }

    /// A relock whose save works holds nothing.
    func testALockWhoseSaveWorks_holdsNothing() async throws {
        let store = RefusingStore()
        let stored = Take(blocks: [.textLine("Written before the lock")])
        try store.upsert(stored)
        let subscription = SubscriptionManager()
        subscription.forceStatusForTesting(.subscribed)
        let app = AppModel(needsOnboarding: false, initialStore: InMemoryTakeStore(), session: SessionController(),
                           makeStoreFromKeys: { _ in store }, unlockKeys: { KeyHierarchy(masterKeyBytes: Data(repeating: 7, count: 32)) },
                           lockState: .locked, subscription: subscription, conflictDirectory: conflictDirectory)
        await app.attemptUnlock()
        var draft = stored
        draft.blocks = [.textLine(typed)]
        app.ui.commitInlineEdit = { _ = app.commitEditedTake(draft) }
        app.relock()
        XCTAssertFalse(app.hasHeldEdit)
        XCTAssertEqual(try store.base.allTakes().map(\.plainText), [typed])
    }

    /// The app went to the background and came back (the session drops its derived keys then,
    /// while the app stays unlocked), and later locks with a refused save: the edit is still held
    /// (Greptile on #475).
    func testAfterATripToTheBackground_aRefusedEditIsStillHeld() async throws {
        let store = RefusingStore()
        let app = try await lockWithARefusedEdit(store, backgroundedFirst: true)
        XCTAssertTrue(app.hasHeldEdit, "nothing was held: the keys were gone after the trip to the background")
        store.refuseWrites = false
        await app.attemptUnlock()
        XCTAssertEqual(try store.allTakes().map(\.plainText), [typed], "the typing was not saved after the unlock")
    }

    /// The typing handed back after the unlock is waiting before the unlocked timeline exists:
    /// the new Dailies opens it in the editor when it appears (Greptile on #475).
    func testATakeHandedBackBeforeTheTimelineExists_opensWhenItAppears() throws {
        let app = AppModel.preview(store: InMemoryTakeStore(), onboarded: true)
        func show() -> UIWindow {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = UIHostingController(rootView: DailiesView()
                .environment(app).environment(app.dailiesVM).environment(app.ui).environment(app.conflictQueue))
            window.makeKeyAndVisible()
            return window
        }
        func settle() { RunLoop.current.run(until: Date().addingTimeInterval(1)) }

        // Control: one set while the timeline is up is opened, so the harness can see it.
        var window = show()
        settle()
        app.ui.pendingInlineNewTake = Take(blocks: [.textLine("Set while shown")])
        settle()
        XCTAssertNil(app.ui.pendingInlineNewTake, "the harness can't see a Take opened, so the test proves nothing")
        // The locked screen replaces the timeline: this one is gone before the Take is handed back.
        window.isHidden = true
        window.rootViewController = nil
        settle()

        app.ui.pendingInlineNewTake = Take(blocks: [.textLine(typed)])
        window = show()
        settle()
        XCTAssertNil(app.ui.pendingInlineNewTake, "the Take handed back before the timeline existed was never opened")
        window.isHidden = true
    }
}
