//
//  ConflictHoldTests.swift
//  CatchlightAppTests
//
//  A Take waiting in the conflict queue is held (owner 2026-10-07: "the file shouldn't
//  update or edit until the conflict is resolved"): every change the app could make to it is
//  refused, sync never uploads it, and the hold survives a relaunch because the queue is kept
//  on disk, sealed. Seams: `AppModel` (the app's edit paths and gates), `ConflictHoldingStore`
//  (the store every edit goes through), `ConflictQueue` (attach / enqueue / skip / resolve) and
//  `BackgroundSyncCoordinator.pass` (the one sync call both sync paths make).
//

#if canImport(Catchlight)
import XCTest
import CryptoKit
@testable import CatchlightCore
@testable import Catchlight

@MainActor
final class ConflictHoldTests: XCTestCase {

    private let keys = KeyHierarchy(masterKeyBytes: Data(repeating: 9, count: 32))
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConflictHoldTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func take(_ text: String, id: UUID = UUID(), isObie: Bool = false) -> Take {
        Take(id: id, modifiedAt: Date(timeIntervalSince1970: 1_000_000),
             blocks: [.textLine(text)], isObie: isObie)
    }

    private func pair(for local: Take, remoteText: String = "from the other device") -> (local: Take, remote: Take) {
        (local: local, remote: take(remoteText, id: local.id))
    }

    /// An unlocked app over `store`, its conflict queue kept in this test's directory.
    private func makeApp(store: InMemoryTakeStore) async -> AppModel {
        let subscription = SubscriptionManager()
        subscription.forceStatusForTesting(.subscribed)
        let keys = self.keys
        let app = AppModel(needsOnboarding: false,
                           initialStore: InMemoryTakeStore(),
                           session: SessionController(),
                           makeStoreFromKeys: { _ in store },
                           unlockKeys: { keys },
                           lockState: .locked,
                           subscription: subscription,
                           conflictDirectory: directory)
        await app.attemptUnlock()
        XCTAssertEqual(app.lockState, .unlocked)
        return app
    }

    // MARK: - The app's edit paths

    /// The owner's report, through the app's own edit path: an edit to a Take waiting for a
    /// conflict choice must not reach the store. (Failed on main before this change: the edit
    /// was written.)
    func testEditToQueuedTake_isNotWritten() throws {
        let store = InMemoryTakeStore()
        let x = take("original")
        try store.upsert(x)
        let app = AppModel.preview(store: store, onboarded: true)
        app.conflictQueue.enqueue([pair(for: x)])

        var edited = x
        edited.primaryText = "edited while waiting"
        app.dailiesVM.save(edited)

        XCTAssertEqual(try store.take(id: x.id)?.primaryText, "original")
        XCTAssertEqual(app.dailiesVM.lastError, Notice.takeAwaitingConflict.message)
    }

    func testEveryViewModelWrite_toAHeldTake_isRefused() async throws {
        let store = InMemoryTakeStore()
        var x = take("held")
        x.setTask(true)
        x.blocks = [.textLine("held"), .checkItem("item", isComplete: false)]
        try store.upsert(x)
        let app = await makeApp(store: store)
        app.conflictQueue.enqueue([pair(for: x)])
        let vm = app.dailiesVM

        vm.toggleDone(x)
        vm.toggleImportant(x)
        vm.designateObie(x, replaceExisting: true)
        vm.delete(x)
        vm.discardIfPresent(x)

        XCTAssertEqual(try store.take(id: x.id), x, "nothing reached the held Take")
        XCTAssertEqual(vm.lastError, Notice.takeAwaitingConflict.message)
    }

    func testGate_refusesHeldTake_andShowsASkippedConflictAgain() async throws {
        let store = InMemoryTakeStore()
        let x = take("held"), y = take("free")
        try store.upsert(x); try store.upsert(y)
        let app = await makeApp(store: store)
        app.conflictQueue.enqueue([pair(for: x)])
        app.conflictQueue.skip(id: x.id)
        XCTAssertTrue(app.conflictQueue.pending.isEmpty)

        XCTAssertFalse(app.ensureEditable(x.id))
        XCTAssertFalse(app.ensureNotHeld(x.id))
        XCTAssertTrue(app.ensureEditable(y.id))
        XCTAssertEqual(app.conflictQueue.pending.map(\.local.id), [x.id], "Review is offered again")
        XCTAssertEqual(app.dailiesVM.lastError, Notice.takeAwaitingConflict.message)
    }

    /// The editor was open when the conflict arrived: the typing is kept as a new Take and the
    /// held Take is untouched.
    func testEditorCommit_onAHeldTake_keepsTheEditAsANewTake() async throws {
        let store = InMemoryTakeStore()
        let x = take("original")
        try store.upsert(x)
        let app = await makeApp(store: store)
        app.conflictQueue.enqueue([pair(for: x)])

        var draft = x
        draft.primaryText = "typed before the conflict arrived"
        XCTAssertEqual(app.commitEditedTake(draft), .savedAsCopy)

        XCTAssertEqual(try store.take(id: x.id)?.primaryText, "original")
        let all = try store.allTakes()
        XCTAssertEqual(all.count, 2)
        let copy = try XCTUnwrap(all.first { $0.id != x.id })
        XCTAssertEqual(copy.primaryText, "typed before the conflict arrived")
        XCTAssertEqual(app.dailiesVM.lastError, Notice.conflictEditKeptAsCopy.message)
    }

    func testEditorCommit_onAHeldTake_withNoChange_writesNothing() async throws {
        let store = InMemoryTakeStore()
        let x = take("original")
        try store.upsert(x)
        let app = await makeApp(store: store)
        app.conflictQueue.enqueue([pair(for: x)])

        XCTAssertEqual(app.commitEditedTake(x), .refusedForConflict)
        XCTAssertEqual(try store.allTakes(), [x])
    }

    // MARK: - The store

    func testHoldingStore_refusesEveryWriteKind_forAHeldTake_andAllowsOthers() throws {
        let base = InMemoryTakeStore()
        let held = HeldTakes()
        let store = ConflictHoldingStore(base: base, held: held)
        let x = take("held"), y = take("free")
        try base.upsert(x); try base.upsert(y)
        held.replace(with: [x.id])

        var edited = x; edited.primaryText = "changed"
        XCTAssertThrowsError(try store.upsert(edited)) { XCTAssertEqual($0 as? TakeHeldForConflict, TakeHeldForConflict(id: x.id)) }
        XCTAssertThrowsError(try store.delete(id: x.id))
        XCTAssertThrowsError(try store.setObie(id: x.id, replaceExisting: true))
        XCTAssertThrowsError(try store.applyRemote(edited))
        XCTAssertThrowsError(try store.release(id: x.id, ifNotModifiedAfter: .distantFuture))
        XCTAssertEqual(try base.take(id: x.id), x)

        var y2 = y; y2.primaryText = "free to change"
        XCTAssertNoThrow(try store.upsert(y2))
        XCTAssertEqual(try base.take(id: y.id)?.primaryText, "free to change")
        XCTAssertNoThrow(try store.delete(id: y.id))
        XCTAssertNil(try base.take(id: y.id))
    }

    /// Making another Take the Obie demotes the current one inside the store: a write to it.
    func testHoldingStore_refusesNewObie_whenTheCurrentObieIsHeld() throws {
        let base = InMemoryTakeStore()
        let held = HeldTakes()
        let store = ConflictHoldingStore(base: base, held: held)
        let obie = take("held Obie", isObie: true), other = take("other")
        try base.upsert(obie); try base.upsert(other)
        held.replace(with: [obie.id])

        XCTAssertThrowsError(try store.setObie(id: other.id, replaceExisting: true))
        var promoted = other; promoted.isObie = true
        XCTAssertThrowsError(try store.upsert(promoted))
        XCTAssertEqual(try base.currentObie()?.id, obie.id)
    }

    // MARK: - On disk

    func testQueue_survivesARelaunch_sealed() throws {
        let x = take("my secret version")
        let first = ConflictQueue()
        first.attach(keys: keys, directory: directory)
        first.enqueue([pair(for: x, remoteText: "their secret version")])

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let bytes = try Data(contentsOf: files[0])
        for plain in ["my secret version", "their secret version", x.id.uuidString] {
            XCTAssertNil(bytes.range(of: Data(plain.utf8)), "no plaintext on disk: \(plain)")
        }

        let relaunched = ConflictQueue()
        XCTAssertFalse(relaunched.isHeld(x.id))
        relaunched.attach(keys: keys, directory: directory)
        XCTAssertTrue(relaunched.isHeld(x.id))
        XCTAssertEqual(relaunched.pending.first?.local.primaryText, "my secret version")
        XCTAssertEqual(relaunched.pending.first?.remote.primaryText, "their secret version")
    }

    /// A file that won't open is kept, and its Take stays held: the owner's rule holds even
    /// when the pair can't be shown.
    func testQueue_aFileThatWontOpen_isKept_andItsTakeStaysHeld() throws {
        let x = take("mine")
        let first = ConflictQueue()
        first.attach(keys: keys, directory: directory)
        first.enqueue([pair(for: x)])

        let other = ConflictQueue()
        other.attach(keys: KeyHierarchy(masterKeyBytes: Data(repeating: 1, count: 32)), directory: directory)
        XCTAssertTrue(other.pending.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
        XCTAssertTrue(other.isHeld(x.id))
        XCTAssertEqual(other.unreadable, [x.id])
    }

    func testUnlock_withAFileThatWontOpen_saysSo() async throws {
        let x = take("mine")
        let first = ConflictQueue()
        first.attach(keys: KeyHierarchy(masterKeyBytes: Data(repeating: 1, count: 32)), directory: directory)
        first.enqueue([pair(for: x)])
        let store = InMemoryTakeStore()
        try store.upsert(x)

        let app = await makeApp(store: store)

        XCTAssertEqual(app.dailiesVM.lastError, Notice.conflictsUnreadable(1).message)
        XCTAssertFalse(app.ensureEditable(x.id))
    }

    // MARK: - Late and stale deliveries

    func testDetached_enqueueDoesNothing_andWritesNoFile() {
        let queue = ConflictQueue()
        queue.attach(keys: keys, directory: directory)
        queue.detach()

        queue.enqueue([pair(for: take("late"))])
        queue.enqueueUnverified([UnverifiedCopy(id: UUID(), local: nil, cloud: take("late"))])

        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertTrue(queue.unverified.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    /// A pass begun before a relock (or a new account) may not deliver into the queue after it.
    func testAPassFromAnEarlierGeneration_isNotCurrent() {
        let queue = ConflictQueue()
        queue.attach(keys: keys, directory: directory)
        let started = queue.held.snapshot.generation
        XCTAssertTrue(BackgroundSyncCoordinator.isCurrent(started, queue.held))

        queue.detach()
        XCTAssertFalse(BackgroundSyncCoordinator.isCurrent(started, queue.held))
        queue.attach(keys: keys, directory: directory)
        XCTAssertFalse(BackgroundSyncCoordinator.isCurrent(started, queue.held))
    }

    // MARK: - Reconciling with sync

    /// Another device made the held Take a Script and the pass let it go: nothing is left to
    /// choose, so the pair, its hold and its file go too.
    func testRelease_dropsThePairItsHoldAndItsFile() throws {
        let x = take("mine"), y = take("other")
        let queue = ConflictQueue()
        queue.attach(keys: keys, directory: directory)
        queue.enqueue([pair(for: x), pair(for: y)])

        queue.release([x.id, UUID()])

        XCTAssertFalse(queue.isHeld(x.id))
        XCTAssertEqual(queue.pending.map(\.local.id), [y.id])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }

    /// Keeping either unverified copy writes the raw store, so a held Take is never offered.
    func testUnverifiedCopy_ofAHeldTake_isNotOffered() {
        let x = take("held"), y = take("free")
        let queue = ConflictQueue()
        queue.enqueue([pair(for: x)])

        queue.enqueueUnverified([UnverifiedCopy(id: x.id, local: x, cloud: take("cloud", id: x.id)),
                                 UnverifiedCopy(id: y.id, local: y, cloud: nil)])

        XCTAssertEqual(queue.unverified.map(\.id), [y.id])
    }

    // MARK: - The Obie

    /// A new Take saved as the Obie while the current Obie is held: the text is kept, as an
    /// ordinary Take, and the user is told. (Before: refused, and the text was lost.)
    func testNewObie_whileTheObieIsHeld_isSavedButNotAsObie() async throws {
        let store = InMemoryTakeStore()
        let obie = take("held Obie", isObie: true)
        try store.upsert(obie)
        let app = await makeApp(store: store)
        app.conflictQueue.enqueue([pair(for: obie)])

        var capture = app.dailiesVM.createTake()
        capture.blocks = [.textLine("dictated to Siri")]
        capture.isObie = true
        XCTAssertTrue(app.dailiesVM.save(capture))

        let saved = try XCTUnwrap(store.take(id: capture.id))
        XCTAssertEqual(saved.primaryText, "dictated to Siri")
        XCTAssertFalse(saved.isObie)
        XCTAssertEqual(try store.currentObie()?.id, obie.id)
        XCTAssertEqual(app.dailiesVM.lastError, Notice.savedNotAsObie.message)
    }

    func testMakingAnotherTakeTheObie_whileTheObieIsHeld_saysWhy() async throws {
        let store = InMemoryTakeStore()
        let obie = take("held Obie", isObie: true), other = take("other")
        try store.upsert(obie); try store.upsert(other)
        let app = await makeApp(store: store)
        app.conflictQueue.enqueue([pair(for: obie)])

        app.dailiesVM.designateObie(other, replaceExisting: true)

        XCTAssertEqual(try store.currentObie()?.id, obie.id)
        XCTAssertEqual(app.dailiesVM.lastError, Notice.obieAwaitingConflict.message)
    }

    // MARK: - Reminder actions and reorder

    /// A "Stop reminding" tapped for a held Take stays queued, and applies once it's resolved.
    /// (Before: drained, refused and lost.)
    func testReminderAction_forAHeldTake_waitsForTheChoice() async throws {
        _ = PendingReminderActions.drainStopReminding()
        _ = PendingReminderActions.drainDismissed()
        defer { _ = PendingReminderActions.drainStopReminding() }
        let store = InMemoryTakeStore()
        var x = take("call the framer")
        x.timeReminder = TimeReminder(scheduledDate: Date().addingTimeInterval(3600),
                                      notificationIdentifier: x.id.uuidString)
        try store.upsert(x)
        let app = await makeApp(store: store)
        app.conflictQueue.enqueue([(local: x, remote: x)])
        PendingReminderActions.enqueueStopReminding(takeID: x.id.uuidString)

        app.dailiesVM.applyPendingReminderActions()
        XCTAssertNotNil(try store.take(id: x.id)?.timeReminder)
        XCTAssertEqual(PendingReminderActions.queuedIDs(), [x.id])

        try app.conflictQueue.resolve(id: x.id, keepLocal: true, store: app.dailiesVM.conflictChoiceStore)
        app.dailiesVM.applyPendingReminderActions()
        XCTAssertNil(try store.take(id: x.id)?.timeReminder)
        XCTAssertTrue(PendingReminderActions.queuedIDs().isEmpty)
    }

    /// A drag whose renumber reaches a held Take writes nothing at all.
    func testReorder_thatWouldRenumberAHeldTake_writesNothing() async throws {
        let store = InMemoryTakeStore()
        var a = take("a"), b = take("b"), c = take("c")
        a.manualOrder = 1
        b.manualOrder = Double(1).nextUp   // no midpoint left: moving between them renumbers
        c.manualOrder = 5
        for t in [a, b, c] { try store.upsert(t) }
        let app = await makeApp(store: store)
        app.conflictQueue.enqueue([pair(for: a)])

        app.dailiesVM.moveTake(c.id, to: 1)

        XCTAssertEqual(try store.allTakes().sorted { $0.primaryText < $1.primaryText }, [a, b, c])
        XCTAssertEqual(app.dailiesVM.lastError, Notice.takeAwaitingConflict.message)
    }

    // MARK: - Single flight

    /// A conflict choice made while a pass runs is pushed by one more pass after it.
    func testATriggerDuringAPass_runsOnceMoreAfterIt() {
        let flight = SyncFlight()
        XCTAssertTrue(flight.begin(.appBecameActive))
        XCTAssertFalse(flight.begin(.saveCommitted))
        XCTAssertFalse(flight.begin(.saveCommitted))
        XCTAssertEqual(flight.end(), .saveCommitted)
        XCTAssertTrue(flight.begin(.saveCommitted))
        XCTAssertNil(flight.end())
    }

    func testAnActivationDuringAPass_isNotRepeated() {
        let flight = SyncFlight()
        XCTAssertTrue(flight.begin(.saveCommitted))
        XCTAssertFalse(flight.begin(.appBecameActive))
        XCTAssertNil(flight.end())
    }

    func testSkip_hidesUntilRelaunch_andTheTakeStaysHeld() {
        let x = take("mine")
        let queue = ConflictQueue()
        queue.attach(keys: keys, directory: directory)
        queue.enqueue([pair(for: x)])
        queue.skip(id: x.id)

        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertTrue(queue.isHeld(x.id))

        let relaunched = ConflictQueue()
        relaunched.attach(keys: keys, directory: directory)
        XCTAssertEqual(relaunched.pending.map(\.local.id), [x.id])
    }

    func testDetach_forgetsTheQueue_andTheNextUnlockLoadsItAgain() {
        let x = take("mine")
        let queue = ConflictQueue()
        queue.attach(keys: keys, directory: directory)
        queue.enqueue([pair(for: x)])

        queue.detach()
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertFalse(queue.isHeld(x.id))

        queue.attach(keys: keys, directory: directory)
        XCTAssertTrue(queue.isHeld(x.id))
    }

    func testResolve_releasesTheHold_andRemovesTheFile() throws {
        let store = InMemoryTakeStore()
        let x = take("mine")
        try store.upsert(x)
        let queue = ConflictQueue()
        queue.attach(keys: keys, directory: directory)
        queue.enqueue([pair(for: x)])

        try queue.resolve(id: x.id, keepLocal: false, store: store)

        XCTAssertFalse(queue.isHeld(x.id))
        XCTAssertEqual(try store.take(id: x.id)?.primaryText, "from the other device")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
        let relaunched = ConflictQueue()
        relaunched.attach(keys: keys, directory: directory)
        XCTAssertTrue(relaunched.pending.isEmpty)
    }

    /// Resolving goes through the raw store even though the app's edits go through the hold.
    func testResolveFromTheApp_writesTheChoice() async throws {
        let store = InMemoryTakeStore()
        let x = take("mine")
        try store.upsert(x)
        let app = await makeApp(store: store)
        app.conflictQueue.enqueue([pair(for: x)])

        try app.conflictQueue.resolve(id: x.id, keepLocal: false, store: app.dailiesVM.conflictChoiceStore)

        XCTAssertEqual(try store.take(id: x.id)?.primaryText, "from the other device")
        var after = try XCTUnwrap(store.take(id: x.id))
        after.primaryText = "editable again"
        app.dailiesVM.save(after)
        XCTAssertEqual(try store.take(id: x.id)?.primaryText, "editable again")
    }

    // MARK: - Sync

    private func cloudText(_ id: UUID, cloud: InMemoryCloudFolder) throws -> String? {
        guard let bytes = try cloud.read(CloudBlob.fileName(for: id)) else { return nil }
        let ct = try XCTUnwrap(CloudBlob.parse(bytes).ciphertext)
        return try TakeCrypto(keys: keys).open(ct, takeUUID: id).primaryText
    }

    /// A Take already in the folder, edited here after its conflict was queued: the pass
    /// leaves the folder's version alone, and uploads the choice once it is made.
    func testSync_holdsAQueuedTake_untilItIsResolved() throws {
        let store = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        let x = take("synced"), y = take("free")
        try store.upsert(x); try store.upsert(y)
        let queue = ConflictQueue()
        let engine = SyncEngine(store: store, cloud: cloud, keys: keys, deviceId: UUID())
        try BackgroundSyncCoordinator.pass(engine, holding: queue.held, isCancelled: { false })
        XCTAssertEqual(try cloudText(x.id, cloud: cloud), "synced")

        queue.enqueue([pair(for: x)])
        for (original, text) in [(x, "changed while held"), (y, "free, changed")] {
            var edited = original
            edited.primaryText = text
            edited.modifiedAt = Date().addingTimeInterval(1)
            try store.upsert(edited)   // the raw store: the engine's view, past any UI gate
        }
        try BackgroundSyncCoordinator.pass(engine, holding: queue.held, isCancelled: { false })
        XCTAssertEqual(try cloudText(x.id, cloud: cloud), "synced", "a held Take is not uploaded")
        XCTAssertEqual(try cloudText(y.id, cloud: cloud), "free, changed")

        try queue.resolve(id: x.id, keepLocal: true, store: store)
        try BackgroundSyncCoordinator.pass(engine, holding: queue.held, isCancelled: { false })
        XCTAssertEqual(try cloudText(x.id, cloud: cloud), "changed while held",
                       "the choice uploads once resolved")
    }
}
#endif
