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
}
#endif
