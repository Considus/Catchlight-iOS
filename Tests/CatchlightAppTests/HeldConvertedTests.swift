//
//  HeldConvertedTests.swift
//  CatchlightAppTests
//
//  Catchlight-Core#29: a Take waiting for a conflict choice that another device then turns into a
//  Script is never let go or forked by sync. Core names it in `SyncReport.heldConverted` on every
//  pass, and the queue marks the pair converted. The phone never reads the Script (D-315), and
//  resolving the pair must never write the Take's own id: the usual choice re-stamps the kept
//  version, and the next push would send it into the Script.
//
//  Seams: `ConflictQueue` (`markConverted`, `resolve`, `resolveConverted`, `attach`) and
//  `BackgroundSyncCoordinator.pass` (the one sync call both sync paths make) on the phone, with
//  Core's real `SyncEngine` on the desktop that keeps Scripts, over one `InMemoryCloudFolder`.
//

#if canImport(Catchlight)
import XCTest
@testable import CatchlightCore
@testable import Catchlight

@MainActor
final class HeldConvertedTests: XCTestCase {

    private let keys = KeyHierarchy(masterKeyBytes: Data(repeating: 5, count: 32))
    private let cloud = InMemoryCloudFolder()
    private let phone = InMemoryTakeStore(), desk = InMemoryTakeStore()
    private let phoneDevice = UUID(), deskDevice = UUID()
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeldConvertedTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// One pass on the phone, its report handed to the queue as `CatchlightApp` wires it.
    @discardableResult
    private func syncPhone(_ queue: ConflictQueue) throws -> SyncReport {
        let engine = SyncEngine(store: phone, cloud: cloud, keys: keys, deviceId: phoneDevice)
        let (report, _) = try BackgroundSyncCoordinator.pass(engine, holding: queue.held, isCancelled: { false })
        defer { queue.held.endPass() }   // as `deliver` does once the report is in
        queue.release(report.deletedLocally)
        queue.enqueue(report.conflicts)
        queue.markConverted(report.heldConverted)
        return report
    }

    @discardableResult
    private func syncDesk() throws -> SyncReport {
        try SyncEngine(store: desk, cloud: cloud, keys: keys, deviceId: deskDevice, holdsScripts: true).sync()
    }

    private func edit(_ store: InMemoryTakeStore, _ id: UUID, _ text: String) throws {
        var take = try XCTUnwrap(store.take(id: id))
        take.primaryText = text
        take.modifiedAt = Date()
        try store.upsert(take)
    }

    private func manifest() throws -> Manifest {
        let data = try XCTUnwrap(cloud.read(Manifest.fileName))
        return try Manifest.opening(ManifestEnvelope.parse(data), with: keys.manifestEncryptionKey())
    }

    /// A Take with a reminder, edited on both devices, its conflict waiting on the phone; then the
    /// desk turns it into a Script and syncs, and the phone's next pass finds it converted.
    private func convertedPair(_ queue: ConflictQueue, obie: Bool = false) throws -> UUID {
        var take = Take(createdAt: Date(timeIntervalSince1970: 1_780_000_000),
                        blocks: [.textLine("Original")], isObie: obie)
        take.timeReminder = TimeReminder(scheduledDate: Date().addingTimeInterval(86_400),
                                         notificationIdentifier: take.id.uuidString)
        try desk.upsert(take)
        try syncDesk()
        try syncPhone(queue)
        try edit(phone, take.id, "Edited on the phone")
        try edit(desk, take.id, "Edited on the desk")
        try syncDesk()
        try syncPhone(queue)
        XCTAssertEqual(queue.pending.map(\.local.id), [take.id], "the conflict waits on the phone")

        var script = try XCTUnwrap(desk.take(id: take.id))
        script.kind = ManifestEntry.Kind.script
        script.modifiedAt = Date()
        try desk.upsert(script)
        try syncDesk()

        let report = try syncPhone(queue)
        XCTAssertEqual(report.heldConverted, [take.id])
        XCTAssertEqual(report.deletedLocally, [], "held, the Take is not let go")
        XCTAssertEqual(report.forkedFromScripts, [], "nor forked")
        XCTAssertTrue(queue.isConverted(take.id))
        XCTAssertTrue(queue.isHeld(take.id))
        XCTAssertEqual(try phone.take(id: take.id)?.primaryText, "Edited on the phone")
        return take.id
    }

    /// The required case: "Keep this version as a new Take" makes a NEW Take and never writes the
    /// original id, so the next sync leaves the Script's entry and file exactly as the desk wrote them.
    func testKeepAsNew_makesANewTake_andNeverWritesTheScript() throws {
        let queue = ConflictQueue()
        let id = try convertedPair(queue)
        let original = try XCTUnwrap(phone.take(id: id))
        let entryBefore = try XCTUnwrap(manifest().takes.first { $0.uuid == id })
        let fileBefore = try XCTUnwrap(cloud.read(CloudBlob.fileName(for: id)))

        // The usual choice re-stamps the Take on its own id: refused, and nothing is written.
        XCTAssertThrowsError(try queue.resolve(id: id, keepLocal: true, store: phone))
        XCTAssertEqual(try phone.take(id: id), original)

        let copy = try XCTUnwrap(try queue.resolveConverted(id: id, keepAsNew: true, store: phone))
        XCTAssertNotEqual(copy.id, id)
        XCTAssertNil(try phone.take(id: id), "the original leaves the phone")
        XCTAssertEqual(try phone.allTakes().map(\.id), [copy.id])
        XCTAssertEqual(copy.primaryText, "Edited on the phone")
        XCTAssertEqual(copy.createdAt, original.createdAt)
        XCTAssertEqual(copy.timeReminder?.notificationIdentifier, copy.id.uuidString, "its own reminder id")
        XCTAssertFalse(copy.isObie)
        XCTAssertFalse(queue.isHeld(id))
        XCTAssertFalse(queue.isConverted(id))

        let next = try syncPhone(queue)
        XCTAssertEqual(next.uploaded, [copy.id], "only the new Take goes up")
        XCTAssertEqual(try manifest().takes.first { $0.uuid == id }, entryBefore, "the Script's entry is untouched")
        XCTAssertEqual(try cloud.read(CloudBlob.fileName(for: id)), fileBefore, "and so is its file")
        XCTAssertFalse(try manifest().tombstones.contains { $0.uuid == id }, "no deletion record for the Script")

        try syncDesk()
        XCTAssertEqual(try desk.take(id: id)?.isScript, true, "the desk's Script is as it left it")
        XCTAssertEqual(try desk.take(id: id)?.primaryText, "Edited on the desk")
        XCTAssertEqual(try desk.take(id: copy.id)?.primaryText, "Edited on the phone")
    }

    func testKeepAsNew_ofTheObie_makesTheCopyTheObie() throws {
        let queue = ConflictQueue()
        let id = try convertedPair(queue, obie: true)

        let copy = try XCTUnwrap(try queue.resolveConverted(id: id, keepAsNew: true, store: phone))

        XCTAssertTrue(copy.isObie)
        XCTAssertEqual(try phone.currentObie()?.id, copy.id)
    }

    /// "Let it go": the pair and the hold go, the Take leaves the phone with no deletion record,
    /// and the Script stays as it was.
    func testLetItGo_dropsTheHold_andLeavesTheScript() throws {
        let queue = ConflictQueue()
        let id = try convertedPair(queue)
        let entryBefore = try XCTUnwrap(manifest().takes.first { $0.uuid == id })
        let fileBefore = try XCTUnwrap(cloud.read(CloudBlob.fileName(for: id)))

        XCTAssertNil(try queue.resolveConverted(id: id, keepAsNew: false, store: phone))

        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertFalse(queue.isHeld(id))
        XCTAssertNil(try phone.take(id: id))
        let next = try syncPhone(queue)
        XCTAssertEqual(next.uploaded, [])
        XCTAssertEqual(try manifest().takes.first { $0.uuid == id }, entryBefore)
        XCTAssertEqual(try cloud.read(CloudBlob.fileName(for: id)), fileBefore)
        XCTAssertFalse(try manifest().tombstones.contains { $0.uuid == id })
        XCTAssertTrue(try phone.allTakes().isEmpty, "and it doesn't come back")
    }

    func testAnOrdinaryPair_refusesTheConvertedChoices() throws {
        let store = InMemoryTakeStore()
        let local = Take(blocks: [.textLine("Mine")])
        try store.upsert(local)
        var remote = local
        remote.primaryText = "Theirs"
        let queue = ConflictQueue()
        queue.enqueue([(local: local, remote: remote)])

        XCTAssertThrowsError(try queue.resolveConverted(id: local.id, keepAsNew: true, store: store))
        XCTAssertThrowsError(try queue.resolveConverted(id: local.id, keepAsNew: false, store: store))
        XCTAssertEqual(try store.allTakes(), [local])
        XCTAssertTrue(queue.isHeld(local.id))
    }

    /// The mark is kept in the pair's sealed file: the next unlock reads the pair as converted, and
    /// shows it again even if it was skipped.
    func testTheMark_survivesAQueueReload() throws {
        let local = Take(blocks: [.textLine("Mine")])
        var remote = local
        remote.primaryText = "Theirs"
        let queue = ConflictQueue()
        queue.attach(keys: keys, directory: directory)
        queue.enqueue([(local: local, remote: remote)])
        queue.skip(id: local.id)
        queue.markConverted([local.id, UUID()])   // an id with no pair is left alone
        XCTAssertEqual(queue.pending.map(\.local.id), [local.id], "a skipped pair is shown again")

        let reloaded = ConflictQueue()
        reloaded.attach(keys: keys, directory: directory)
        XCTAssertTrue(reloaded.isConverted(local.id))
        XCTAssertTrue(reloaded.isHeld(local.id))

        try reloaded.resolveConverted(id: local.id, keepAsNew: false, store: InMemoryTakeStore())
        let again = ConflictQueue()
        again.attach(keys: keys, directory: directory)
        XCTAssertFalse(again.isHeld(local.id), "resolved, nothing waits after a reload")
    }

    // MARK: - Review of 33f3532

    /// An unlocked app over `store`, its conflict queue kept in this test's directory.
    private func makeApp(store: InMemoryTakeStore) async -> AppModel {
        let subscription = SubscriptionManager()
        subscription.forceStatusForTesting(.subscribed)
        let keys = self.keys
        let app = AppModel(needsOnboarding: false, initialStore: InMemoryTakeStore(),
                           session: SessionController(), makeStoreFromKeys: { _ in store },
                           unlockKeys: { keys }, lockState: .locked, subscription: subscription,
                           conflictDirectory: directory)
        await app.attemptUnlock()
        return app
    }

    private func waitingPair(in store: InMemoryTakeStore, _ queue: ConflictQueue, text: String = "Mine") throws -> Take {
        let local = Take(blocks: [.textLine(text)])
        try store.upsert(local)
        var remote = local
        remote.primaryText = "Theirs"
        queue.enqueue([(local: local, remote: remote)])
        return local
    }

    /// HIGH: a choice made while a pass runs waits for the pass's report. When that report marks
    /// the pair converted, the usual choice is refused and the original id is never re-stamped.
    func testAChoiceDuringAPass_waitsForItsReport() throws {
        let store = InMemoryTakeStore()
        let queue = ConflictQueue()
        let local = try waitingPair(in: store, queue)
        queue.held.beginPass()

        var outcome: String?
        queue.held.whenNoPassRunning {
            do { try queue.resolve(id: local.id, keepLocal: true, store: store); outcome = "written" }
            catch { outcome = "refused" }
        }
        XCTAssertNil(outcome, "nothing runs while the pass is in flight")

        queue.markConverted([local.id])   // the report the pass delivers
        queue.held.endPass()

        XCTAssertEqual(outcome, "refused")
        XCTAssertEqual(try store.take(id: local.id), local, "the original id is not re-stamped")
        XCTAssertTrue(queue.isConverted(local.id))
    }

    /// The fallback: the choice got in first anyway (the original id re-stamped, the pair gone).
    /// The report's id is kept as a new Take and the original let go, so it can't go into the Script.
    func testAChoiceThatRacedTheConversion_isKeptAsANewTake() async throws {
        let store = InMemoryTakeStore()
        let app = await makeApp(store: store)
        let local = try waitingPair(in: store, app.conflictQueue)
        try app.conflictQueue.resolve(id: local.id, keepLocal: true, store: app.dailiesVM.conflictChoiceStore)

        app.handleHeldConverted([local.id])

        XCTAssertNil(try store.take(id: local.id), "the original id leaves the phone")
        let all = try store.allTakes()
        XCTAssertEqual(all.map(\.primaryText), ["Mine"])
        XCTAssertNotEqual(all.first?.id, local.id)
        XCTAssertTrue(app.conflictQueue.held.isRetired(local.id))
    }

    /// A "Stop reminding" tapped while the Take was held applies to the copy, not comes back on it.
    func testKeepAsNew_appliesAReminderActionTappedWhileHeld() async throws {
        _ = PendingReminderActions.drainStopReminding()
        _ = PendingReminderActions.drainDismissed()
        defer { _ = PendingReminderActions.drainStopReminding(); _ = PendingReminderActions.drainDismissed() }
        let store = InMemoryTakeStore()
        let app = await makeApp(store: store)
        var local = Take(blocks: [.textLine("Call the framer")])
        local.timeReminder = TimeReminder(scheduledDate: Date().addingTimeInterval(3600), notificationIdentifier: local.id.uuidString)
        try store.upsert(local)
        app.conflictQueue.enqueue([(local: local, remote: local)])
        app.conflictQueue.markConverted([local.id])
        PendingReminderActions.enqueueStopReminding(takeID: local.id.uuidString)
        app.dailiesVM.applyPendingReminderActions()   // held: it waits

        let copy = try XCTUnwrap(try app.conflictQueue.resolveConverted(id: local.id, keepAsNew: true, store: app.dailiesVM.conflictChoiceStore))
        app.dailiesVM.applyConvertedChoice(released: local.id, keptAs: copy)

        XCTAssertNil(try store.take(id: copy.id)?.timeReminder, "the stop applies to the copy")
        XCTAssertTrue(PendingReminderActions.queuedIDs().isEmpty)
    }

    /// The other device turned the Script back into a Take: the pass reports an ordinary pair and
    /// the converted mark goes, here and on disk.
    func testAnOrdinaryPairForAConvertedId_clearsTheMark() throws {
        let queue = ConflictQueue()
        queue.attach(keys: keys, directory: directory)
        let local = try waitingPair(in: phone, queue)
        queue.markConverted([local.id])
        var again = local
        again.primaryText = "A Take again"
        queue.enqueue([(local: local, remote: again)])

        XCTAssertFalse(queue.isConverted(local.id))
        let reloaded = ConflictQueue()
        reloaded.attach(keys: keys, directory: directory)
        XCTAssertFalse(reloaded.isConverted(local.id))
    }

    /// A failure partway through keep-as-new leaves the pair; the retry, after a reload as after
    /// a crash, finds the copy already made and makes no second one.
    func testKeepAsNew_retriedAfterAFailure_makesOneCopy() throws {
        let queue = ConflictQueue()
        queue.attach(keys: keys, directory: directory)
        let local = try waitingPair(in: phone, queue)
        queue.markConverted([local.id])
        let flaky = FlakyStore(phone, failReleases: 1)

        XCTAssertThrowsError(try queue.resolveConverted(id: local.id, keepAsNew: true, store: flaky))
        XCTAssertTrue(queue.isHeld(local.id))
        let reloaded = ConflictQueue()
        reloaded.attach(keys: keys, directory: directory)
        let copy = try XCTUnwrap(try reloaded.resolveConverted(id: local.id, keepAsNew: true, store: flaky))

        XCTAssertEqual(try phone.allTakes().map(\.id), [copy.id])
    }

    /// The Obie can't be handed over: the copy stands and the pair is gone, so no retry can copy again.
    func testKeepAsNew_whenTheObieCantMove_stillEndsThePair() throws {
        let queue = ConflictQueue()
        let local = Take(blocks: [.textLine("Obie")], isObie: true)
        try phone.upsert(local)
        queue.enqueue([(local: local, remote: local)])
        queue.markConverted([local.id])

        let copy = try XCTUnwrap(try queue.resolveConverted(id: local.id, keepAsNew: true, store: FlakyStore(phone, failSetObie: true)))

        XCTAssertFalse(queue.isHeld(local.id))
        XCTAssertEqual(try phone.allTakes().map(\.id), [copy.id])
    }

    /// An inline edit still open when the sheet let the Take go: its commit is kept as a new Take,
    /// and nothing ever writes the original id again.
    func testAnEditorLeftOpen_afterLetItGo_neverWritesTheOriginal() async throws {
        let store = InMemoryTakeStore()
        let app = await makeApp(store: store)
        let local = try waitingPair(in: store, app.conflictQueue)
        app.conflictQueue.markConverted([local.id])
        _ = try app.conflictQueue.resolveConverted(id: local.id, keepAsNew: false, store: app.dailiesVM.conflictChoiceStore)

        var draft = local
        draft.primaryText = "typed while the sheet was up"
        XCTAssertEqual(app.commitEditedTake(draft), .savedAsCopy)
        app.dailiesVM.save(draft)   // any other route is refused by the store

        XCTAssertNil(try store.take(id: local.id))
        XCTAssertEqual(try store.allTakes().map(\.primaryText), ["typed while the sheet was up"])
    }

    /// Review of #339: a let-go original stays retired across a relock (a new generation). An
    /// editor left open over the relock must not write it back under its old id.
    func testARetiredOriginal_staysRetiredAcrossANewGeneration() {
        let held = HeldTakes()
        let id = UUID()
        held.retire(id)
        held.newGeneration()
        XCTAssertTrue(held.isRetired(id))
    }

}

/// A store that fails on cue, for the partial-failure cases.
private final class FlakyStore: TakeStore {
    let base: InMemoryTakeStore
    var failReleases: Int
    let failSetObie: Bool
    init(_ base: InMemoryTakeStore, failReleases: Int = 0, failSetObie: Bool = false) {
        self.base = base; self.failReleases = failReleases; self.failSetObie = failSetObie
    }
    struct Failed: Error {}
    func release(id: UUID, ifNotModifiedAfter cutoff: Date) throws -> Bool {
        if failReleases > 0 { failReleases -= 1; throw Failed() }
        return try base.release(id: id, ifNotModifiedAfter: cutoff)
    }
    func setObie(id: UUID, replaceExisting: Bool) throws {
        if failSetObie { throw Failed() }
        try base.setObie(id: id, replaceExisting: replaceExisting)
    }
    func upsert(_ take: Take) throws { try base.upsert(take) }
    func delete(id: UUID) throws { try base.delete(id: id) }
    func applyRemote(_ take: Take) throws -> Bool { try base.applyRemote(take) }
    func take(id: UUID) throws -> Take? { try base.take(id: id) }
    func allTakes() throws -> [Take] { try base.allTakes() }
    func takesModified(since date: Date?) throws -> [Take] { try base.takesModified(since: date) }
    func search(_ query: String) throws -> [Take] { try base.search(query) }
    func upsert(_ sequence: CatchlightSequence) throws { try base.upsert(sequence) }
    func sequence(id: UUID) throws -> CatchlightSequence? { try base.sequence(id: id) }
    func allSequences() throws -> [CatchlightSequence] { try base.allSequences() }
    func deleteSequence(id: UUID) throws { try base.deleteSequence(id: id) }
    func currentObie() throws -> Take? { try base.currentObie() }
    func lastSyncDate() -> Date? { base.lastSyncDate() }
    func setLastSyncDate(_ date: Date) { base.setLastSyncDate(date) }
    func tombstones() throws -> [Tombstone] { try base.tombstones() }
    func purgeTombstones(ids: [UUID]) throws { try base.purgeTombstones(ids: ids) }
}

#endif
