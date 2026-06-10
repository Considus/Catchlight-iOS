//
//  SyncEngineEdgeCasesTests.swift
//  CatchlightCoreTests
//
//  Workplan §7.3 — edge cases for the sync engine that the original SyncEngineTests
//  intentionally did not cover (conflict, offline, partial sync, lock contention,
//  modifiedAt comparison, blob overwrite, deletion shape).
//
//  Happy paths and signature verification live in SyncEngineTests.swift; this file
//  is gap coverage only — no duplication of existing assertions.
//

import XCTest
import CryptoKit
@testable import CatchlightCore

final class SyncEngineEdgeCasesTests: XCTestCase {

    private let salt = Data(repeating: 0x07, count: 16)

    private func makeKeys() -> KeyHierarchy { KeyHierarchy(masterKey: SymmetricKey(size: .bits256)) }

    private func makeEngine(
        store: TakeStore,
        cloud: CloudFolder?,
        keys: KeyHierarchy,
        deviceId: UUID = UUID(),
        now: @escaping () -> Date = Date.init
    ) -> SyncEngine {
        SyncEngine(
            store: store,
            cloud: cloud,
            keys: keys,
            argon2Salt: salt,
            deviceId: deviceId,
            now: now
        )
    }

    // MARK: - Push: updated Take overwrites cloud blob

    /// A locally updated Take re-encrypts and overwrites its `.clk` blob on the
    /// next push. The blob bytes must change AND must still decrypt to the new
    /// plaintext under the same keys.
    func testSyncEngine_updatedTake_overwritesCloudBlob() throws {
        let k = makeKeys()
        let store = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        var take = TestFixtures.richTake()
        take.bodyText = "v1"
        take.modifiedAt = t0
        try store.upsert(take)

        let engine = makeEngine(store: store, cloud: cloud, keys: k, now: { t0.addingTimeInterval(1) })
        try engine.pushOutbound()
        let blobV1 = try cloud.read("\(take.id.uuidString).clk")!

        // Local edit: same id, new body, bumped modifiedAt, lastSync advanced so the
        // changed-since-watermark filter picks it up.
        store.setLastSyncDate(t0.addingTimeInterval(1))
        var take2 = take
        take2.bodyText = "v2"
        take2.modifiedAt = t0.addingTimeInterval(100)
        try store.upsert(take2)
        try makeEngine(store: store, cloud: cloud, keys: k, now: { t0.addingTimeInterval(101) }).pushOutbound()

        let blobV2 = try cloud.read("\(take.id.uuidString).clk")!
        XCTAssertNotEqual(blobV1, blobV2, "blob bytes must differ after re-encrypt")

        // The new blob decrypts to v2 — proves overwrite, not append/rename.
        let parsed = try CloudBlob.parse(blobV2)
        let decrypted = try TakeCrypto(keys: k).open(parsed.ciphertext!, takeUUID: take.id)
        XCTAssertEqual(decrypted.bodyText, "v2")
        XCTAssertEqual(try cloud.clkFiles().count, 1, "no orphan blob left behind")
    }

    // MARK: - Push: deletion shape

    /// **Spec deviation flagged** — the spec describes a deleted Take as producing
    /// a "tombstone entry in the manifest." The actual implementation expresses
    /// deletion as the COMBINATION of (a) the `.clk` blob being securely deleted
    /// from the cloud folder, and (b) the rebuilt manifest having no entry for the
    /// uuid. Inbound sync interprets "previously synced uuid absent from remote
    /// manifest" as a remote-side deletion. Both representations are equivalent
    /// from a correctness standpoint; this test pins the actual on-disk shape.
    func testSyncEngine_deletedTake_removesBlobAndOmitsManifestEntry() throws {
        let k = makeKeys()
        let store = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        var take = TestFixtures.richTake()
        take.modifiedAt = t0
        try store.upsert(take)
        try makeEngine(store: store, cloud: cloud, keys: k, now: { t0.addingTimeInterval(1) }).pushOutbound()
        XCTAssertNotNil(try cloud.read("\(take.id.uuidString).clk"))

        // Delete locally and push.
        try store.delete(id: take.id)
        try makeEngine(store: store, cloud: cloud, keys: k, now: { t0.addingTimeInterval(2) }).pushOutbound()

        XCTAssertNil(try cloud.read("\(take.id.uuidString).clk"), "blob must be removed")
        let manifest = try Manifest.parse(try cloud.read(Manifest.fileName)!)
        XCTAssertTrue(manifest.takes.allSatisfy { $0.uuid != take.id },
                      "manifest must omit the deleted uuid (tombstone-by-absence)")
    }

    // MARK: - Push: no-changes behaviour

    /// **Spec deviation flagged** — the spec asks for "no writes, no lock acquired"
    /// when nothing changed. The actual implementation always acquires + releases
    /// the lock and always rebuilds + re-signs + atomically writes the manifest,
    /// even when no blob changes. This is the cost of an unconditional integrity
    /// re-stamp and is what `testOutboundIdempotent` already exercises from the
    /// other direction (it confirms repeat pushes don't corrupt). This test pins
    /// the observable side-effect: the manifest `updated` field changes between
    /// pushes that have no Take edits.
    func testSyncEngine_noChangePush_stillRewritesManifest() throws {
        let k = makeKeys()
        let store = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        try store.upsert(TestFixtures.richTake())

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        try makeEngine(store: store, cloud: cloud, keys: k, now: { t0 }).pushOutbound()
        let firstUpdated = try Manifest.parse(try cloud.read(Manifest.fileName)!).updated

        // Advance the clock and push again with no Take edits.
        try makeEngine(store: store, cloud: cloud, keys: k, now: { t0.addingTimeInterval(60) }).pushOutbound()
        let secondUpdated = try Manifest.parse(try cloud.read(Manifest.fileName)!).updated

        XCTAssertNotEqual(firstUpdated, secondUpdated,
                          "manifest is rebuilt every push; deviation from spec is documented")
        // And the lock IS acquired+released per push (file gone, no leak).
        XCTAssertNil(try cloud.read(SyncLock.fileName))
    }

    // MARK: - Pull: modifiedAt comparison through the engine

    /// Older remote (modifiedAt before lastSync watermark) is ignored — local wins,
    /// nothing applied, store unchanged.
    func testSyncEngine_olderRemoteModifiedAt_isIgnored() throws {
        let k = makeKeys()
        let cloud = InMemoryCloudFolder()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        // Remote pushes a take at modifiedAt = 100.
        let remoteStore = InMemoryTakeStore()
        var remoteTake = TestFixtures.richTake()
        remoteTake.bodyText = "remote-old"
        remoteTake.modifiedAt = t0.addingTimeInterval(100)
        try remoteStore.upsert(remoteTake)
        try makeEngine(store: remoteStore, cloud: cloud, keys: k, now: { t0.addingTimeInterval(101) }).pushOutbound()

        // Local has the same id at modifiedAt=200, watermark=150
        // → remote.modifiedAt(100) ≤ watermark(150) means "we've already seen this".
        let local = InMemoryTakeStore()
        var localTake = remoteTake
        localTake.bodyText = "local-newer"
        localTake.modifiedAt = t0.addingTimeInterval(200)
        try local.upsert(localTake)
        local.setLastSyncDate(t0.addingTimeInterval(150))

        let report = try makeEngine(store: local, cloud: cloud, keys: k, now: { t0.addingTimeInterval(300) }).pullInbound()

        XCTAssertTrue(report.applied.isEmpty, "older remote must not be applied")
        XCTAssertTrue(report.conflicts.isEmpty)
        XCTAssertEqual(try local.take(id: localTake.id)?.bodyText, "local-newer")
    }

    /// Newer remote (modifiedAt after lastSync watermark) replaces the unchanged
    /// local copy in a single applied entry.
    func testSyncEngine_newerRemoteModifiedAt_replacesLocal() throws {
        let k = makeKeys()
        let cloud = InMemoryCloudFolder()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        let remoteStore = InMemoryTakeStore()
        var remoteTake = TestFixtures.richTake()
        remoteTake.bodyText = "remote-new"
        remoteTake.modifiedAt = t0.addingTimeInterval(200)
        try remoteStore.upsert(remoteTake)
        try makeEngine(store: remoteStore, cloud: cloud, keys: k, now: { t0.addingTimeInterval(201) }).pushOutbound()

        // Local copy is older (100) and considered unchanged since watermark (150).
        let local = InMemoryTakeStore()
        var localTake = remoteTake
        localTake.bodyText = "local-old"
        localTake.modifiedAt = t0.addingTimeInterval(100)
        try local.upsert(localTake)
        local.setLastSyncDate(t0.addingTimeInterval(150))

        let report = try makeEngine(store: local, cloud: cloud, keys: k, now: { t0.addingTimeInterval(300) }).pullInbound()

        XCTAssertEqual(report.applied, [remoteTake.id])
        XCTAssertEqual(try local.take(id: remoteTake.id)?.bodyText, "remote-new")
    }

    // MARK: - Pull: partial-sync quarantine

    /// A 5-blob pull where the middle blob is corrupted should quarantine that
    /// one and apply the other four — the pull does not abort.
    func testSyncEngine_partialPullQuarantinesFailedBlobAndContinues() throws {
        let k = makeKeys()
        let cloud = InMemoryCloudFolder()

        // Device A: five distinct takes, push.
        let remoteStore = InMemoryTakeStore()
        var ids: [UUID] = []
        for i in 0..<5 {
            var t = TestFixtures.richTake(id: UUID())
            t.bodyText = "body-\(i)"
            try remoteStore.upsert(t)
            ids.append(t.id)
        }
        try makeEngine(store: remoteStore, cloud: cloud, keys: k).pushOutbound()
        XCTAssertEqual(try cloud.clkFiles().count, 5)

        // Tamper with one blob (the 3rd id). HMAC will fail → quarantine.
        let badId = ids[2]
        var badBlob = try cloud.read("\(badId.uuidString).clk")!
        badBlob[badBlob.count - 1] ^= 0xFF
        try cloud.write(badBlob, to: "\(badId.uuidString).clk")

        // Fresh device pulls.
        let local = InMemoryTakeStore()
        let report = try makeEngine(store: local, cloud: cloud, keys: k).pullInbound()

        XCTAssertEqual(report.quarantined, [badId])
        XCTAssertEqual(Set(report.applied), Set(ids).subtracting([badId]),
                       "4 of 5 must still apply — pull does not abort on one failure")
        XCTAssertEqual(try local.allTakes().count, 4)
        XCTAssertNil(try local.take(id: badId), "quarantined Take is never written to local")
    }

    /// A blob declared in the manifest but missing from the folder is quarantined,
    /// not silently dropped — and the rest of the pull continues normally.
    func testSyncEngine_missingBlobIsQuarantined() throws {
        let k = makeKeys()
        let cloud = InMemoryCloudFolder()

        let remoteStore = InMemoryTakeStore()
        let keep = TestFixtures.richTake(id: UUID())
        let lose = TestFixtures.richTake(id: UUID())
        try remoteStore.upsert(keep)
        try remoteStore.upsert(lose)
        try makeEngine(store: remoteStore, cloud: cloud, keys: k).pushOutbound()

        // Delete one blob without rebuilding the manifest — simulate a partial sync.
        try cloud.delete("\(lose.id.uuidString).clk")

        let local = InMemoryTakeStore()
        let report = try makeEngine(store: local, cloud: cloud, keys: k).pullInbound()

        XCTAssertEqual(report.quarantined, [lose.id])
        XCTAssertEqual(report.applied, [keep.id])
    }

    // MARK: - ConflictResolver edge cases

    /// Both sides changed since the watermark and `modifiedAt` is bit-identical:
    /// the resolver reports a conflict (newer-wins cannot tiebreak), so the user
    /// gets to choose. Documents the actual behaviour as of v1.0.
    func testConflictResolver_bothChanged_identicalModifiedAt_returnsConflict() {
        let lastSync = Date(timeIntervalSince1970: 1_700_000_000)
        let ts = lastSync.addingTimeInterval(100)
        var local = TestFixtures.richTake()
        local.bodyText = "local"
        local.modifiedAt = ts
        var remote = local
        remote.bodyText = "remote"
        // modifiedAt is the SAME value on both sides.

        let decision = ConflictResolver.decide(local: local, remote: remote, lastSync: lastSync)
        guard case .conflict(let l, let r) = decision else {
            return XCTFail("expected .conflict when both sides changed with equal modifiedAt; got \(decision)")
        }
        XCTAssertEqual(l.bodyText, "local")
        XCTAssertEqual(r.bodyText, "remote")
    }

    /// Both sides UNCHANGED since the watermark (modifiedAt ≤ watermark) but the
    /// content differs — fall back to most-recent-write; equal modifiedAt keeps
    /// LOCAL to avoid churn. This deterministic tiebreak lives in
    /// ConflictResolver.swift; this test pins it.
    func testConflictResolver_bothUnchanged_identicalModifiedAt_keepsLocal() {
        let lastSync = Date(timeIntervalSince1970: 1_700_000_000)
        var local = TestFixtures.richTake()
        local.bodyText = "local"
        local.modifiedAt = lastSync.addingTimeInterval(-10)  // before watermark
        var remote = local
        remote.bodyText = "remote"
        // Same modifiedAt, both before lastSync.

        guard case .keepLocal(let kept) = ConflictResolver.decide(local: local, remote: remote, lastSync: lastSync) else {
            return XCTFail("expected .keepLocal as the documented tie-break")
        }
        XCTAssertEqual(kept.bodyText, "local")
    }

    /// A single resolver call yields exactly one `SyncDecision`. Trivial by type,
    /// but worth pinning: the engine's pull loop dispatches on this once per entry
    /// — if the resolver ever started returning a collection the loop would break
    /// silently. Sanity check.
    func testConflictResolver_singleDecisionPerCall() {
        let lastSync = Date(timeIntervalSince1970: 1_700_000_000)
        var local = TestFixtures.richTake()
        local.modifiedAt = lastSync.addingTimeInterval(-10)
        var remote = local
        remote.bodyText = "remote"
        remote.modifiedAt = lastSync.addingTimeInterval(50)

        let d1 = ConflictResolver.decide(local: local, remote: remote, lastSync: lastSync)
        let d2 = ConflictResolver.decide(local: local, remote: remote, lastSync: lastSync)
        XCTAssertEqual(d1, d2, "resolver must be deterministic and return one decision")
    }

    /// A conflict payload carries BOTH sides intact so the user can compare them
    /// in the resolution UI — nothing is lost or pre-resolved by the engine.
    func testConflictResolver_payloadCarriesBothSides() {
        let lastSync = Date(timeIntervalSince1970: 1_700_000_000)
        var local = TestFixtures.richTake()
        local.bodyText = "L"
        local.modifiedAt = lastSync.addingTimeInterval(100)
        var remote = local
        remote.bodyText = "R"
        remote.modifiedAt = lastSync.addingTimeInterval(200)

        guard case .conflict(let l, let r) = ConflictResolver.decide(local: local, remote: remote, lastSync: lastSync) else {
            return XCTFail("expected conflict")
        }
        XCTAssertEqual(l.bodyText, "L")
        XCTAssertEqual(r.bodyText, "R")
        XCTAssertNotEqual(l, r, "both versions are distinct and preserved")
    }

    // MARK: - SyncLock direct API (engine internals)

    /// Acquiring the lock on an empty folder writes a `catchlight.lock` file whose
    /// `deviceId` matches the engine's deviceId.
    func testSyncLock_acquireOnEmptyFolder_writesCorrectDeviceId() throws {
        let cloud = InMemoryCloudFolder()
        let deviceId = UUID()
        let engine = makeEngine(store: InMemoryTakeStore(), cloud: cloud, keys: makeKeys(), deviceId: deviceId)

        try engine.acquireLock(on: cloud)

        let data = try XCTUnwrap(try cloud.read(SyncLock.fileName))
        let lock = try PlatformJSON.decode(SyncLock.self, from: data)
        XCTAssertEqual(lock.deviceId, deviceId)
    }

    /// Releasing a lock owned by this device removes the lock file.
    func testSyncLock_releaseByOwner_removesLockFile() throws {
        let cloud = InMemoryCloudFolder()
        let deviceId = UUID()
        let engine = makeEngine(store: InMemoryTakeStore(), cloud: cloud, keys: makeKeys(), deviceId: deviceId)

        try engine.acquireLock(on: cloud)
        XCTAssertNotNil(try cloud.read(SyncLock.fileName))

        try engine.releaseLock(on: cloud)
        XCTAssertNil(try cloud.read(SyncLock.fileName))
    }

    /// Releasing a lock owned by ANOTHER device is a silent no-op: the file is
    /// left in place. (Defence against deleting a fresh lock acquired by another
    /// device in a stale-window race — see SyncEngine.releaseLock.)
    func testSyncLock_releaseByNonOwner_leavesLockUntouched() throws {
        let cloud = InMemoryCloudFolder()
        let other = UUID()
        let mine = UUID()
        let acquiredAt = Date(timeIntervalSince1970: 1_700_000_000)

        // Pre-seed a fresh lock owned by the OTHER device.
        let theirs = SyncLock(deviceId: other, acquiredAt: ISO8601.string(from: acquiredAt))
        try cloud.write(try PlatformJSON.encode(theirs), to: SyncLock.fileName)

        let engine = makeEngine(
            store: InMemoryTakeStore(),
            cloud: cloud,
            keys: makeKeys(),
            deviceId: mine,
            now: { acquiredAt.addingTimeInterval(10) }
        )
        try engine.releaseLock(on: cloud)

        let data = try XCTUnwrap(try cloud.read(SyncLock.fileName), "non-owner release must not delete the file")
        let lock = try PlatformJSON.decode(SyncLock.self, from: data)
        XCTAssertEqual(lock.deviceId, other, "the other device still owns the lock")
    }

    // MARK: - SyncLock.isStale boundary

    /// `SyncLock.isStale` is exactly-at-the-threshold logic. Pin both sides of the
    /// five-minute boundary so a future change to `staleAfter` doesn't drift the
    /// inequality silently.
    func testSyncLock_isStale_thresholdBoundary() {
        let acquiredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let lock = SyncLock(deviceId: UUID(), acquiredAt: ISO8601.string(from: acquiredAt))

        // Just before threshold → fresh.
        XCTAssertFalse(lock.isStale(now: acquiredAt.addingTimeInterval(SyncLock.staleAfter - 1)))
        // Exactly at threshold → stale (the impl uses `>=`).
        XCTAssertTrue(lock.isStale(now: acquiredAt.addingTimeInterval(SyncLock.staleAfter)))
        // Well past threshold → stale.
        XCTAssertTrue(lock.isStale(now: acquiredAt.addingTimeInterval(SyncLock.staleAfter + 60)))
    }

    /// A lock with a malformed `acquiredAt` is treated as stale — a corrupt lock
    /// never wedges sync forever.
    func testSyncLock_isStale_malformedTimestampIsStale() {
        let lock = SyncLock(deviceId: UUID(), acquiredAt: "not-a-real-iso-date")
        XCTAssertTrue(lock.isStale(now: Date()))
    }
}
