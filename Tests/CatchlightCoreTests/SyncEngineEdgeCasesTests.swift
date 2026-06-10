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

    private func makeKeys() -> KeyHierarchy { KeyHierarchy(masterKey: SymmetricKey(size: .bits256)) }

    private func makeEngine(
        store: TakeStore,
        cloud: CloudFolder?,
        keys: KeyHierarchy,
        deviceId: UUID = UUID(),
        now: @escaping () -> Date = Date.init
    ) -> SyncEngine {
        TestFixtures.engine(store: store, cloud: cloud, keys: keys, deviceId: deviceId, now: now)
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

    // MARK: - Push: deletion shape (explicit manifest tombstones, 2026-06-10)

    /// A deleted Take produces an EXPLICIT `ManifestTombstone` (manifest v2):
    /// the `.clk` blob is removed, the manifest entry is dropped, AND the
    /// manifest's `tombstones` array carries the uuid + deletion timestamp.
    /// Deletion-by-absence is gone — absence now means "unknown here".
    /// The local tombstone is retained through the push (a concurrent device's
    /// manifest write can clobber ours during cloud propagation, and a purged
    /// tombstone would never re-propagate) and purged only once OBSERVED in a
    /// PULLED manifest.
    func testSyncEngine_deletedTake_removesBlobAndRecordsManifestTombstone() throws {
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
        try makeEngine(store: store, cloud: cloud, keys: k, now: Date.init).pushOutbound()

        XCTAssertNil(try cloud.read("\(take.id.uuidString).clk"), "blob must be removed")
        let manifest = try Manifest.parse(try cloud.read(Manifest.fileName)!)
        XCTAssertEqual(manifest.version, Manifest.currentVersion)
        XCTAssertTrue(manifest.takes.allSatisfy { $0.uuid != take.id },
                      "manifest must omit the deleted uuid from `takes`")
        XCTAssertEqual(manifest.tombstones.map(\.uuid), [take.id],
                       "manifest must carry an explicit tombstone for the deleted uuid")
        XCTAssertNotNil(ISO8601.date(from: manifest.tombstones[0].deletedAt),
                        "tombstone deletedAt must be a parseable ISO-8601 stamp")
        // Push does NOT purge — the local tombstone re-merges idempotently on
        // every push until a PULL observes it in the manifest.
        XCTAssertEqual(try store.tombstones().map(\.id), [take.id],
                       "local tombstone is retained until observed in a pulled manifest")

        // Pull our own manifest back: the tombstone is now durably observed →
        // purged locally.
        try makeEngine(store: store, cloud: cloud, keys: k, now: Date.init).pullInbound()
        XCTAssertTrue(try store.tombstones().isEmpty,
                      "local tombstone is purged once observed in a pulled manifest")
    }

    /// A local Take ABSENT from the remote manifest is NOT deleted on pull
    /// (deletion-by-absence is gone); the next push uploads it (self-heal).
    func testSyncEngine_localTakeAbsentFromManifest_survivesPullAndSelfHealsOnPush() throws {
        let k = makeKeys()
        let cloud = InMemoryCloudFolder()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        // Remote manifest knows only X.
        let remoteStore = InMemoryTakeStore()
        let x = TestFixtures.richTake(id: UUID())
        try remoteStore.upsert(x)
        try makeEngine(store: remoteStore, cloud: cloud, keys: k, now: { t0 }).pushOutbound()

        // Local has X (synced) and Y — previously synced, but somehow missing
        // from the remote manifest (e.g. an earlier watermark race). Y's
        // modifiedAt is BELOW the watermark, which under the old absence model
        // meant "remotely deleted".
        let local = InMemoryTakeStore()
        try local.upsert(x)
        var y = TestFixtures.richTake(id: UUID())
        y.modifiedAt = t0.addingTimeInterval(-100)
        try local.upsert(y)
        local.setLastSyncDate(t0.addingTimeInterval(50))

        let pull = try makeEngine(store: local, cloud: cloud, keys: k, now: { t0.addingTimeInterval(60) }).pullInbound()
        XCTAssertTrue(pull.deletedLocally.isEmpty, "absence must never be read as deletion")
        XCTAssertNotNil(try local.take(id: y.id))

        // Self-heal: the next push uploads Y even though it is below the watermark.
        let push = try makeEngine(store: local, cloud: cloud, keys: k, now: { t0.addingTimeInterval(70) }).pushOutbound()
        XCTAssertTrue(push.uploaded.contains(y.id), "missing manifest entry must be re-uploaded")
        XCTAssertNotNil(try cloud.read("\(y.id.uuidString).clk"))
    }

    /// Edit-wins: a remote tombstone whose deletedAt is OLDER than the local
    /// edit's modifiedAt does not delete the local Take.
    func testSyncEngine_remoteTombstoneOlderThanLocalEdit_editWins() throws {
        let k = makeKeys()
        let cloud = InMemoryCloudFolder()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        // Device A pushes, then deletes at t0+10 and pushes the tombstone.
        let storeA = InMemoryTakeStore()
        var take = TestFixtures.richTake()
        take.modifiedAt = t0
        try storeA.upsert(take)
        try makeEngine(store: storeA, cloud: cloud, keys: k, now: { t0.addingTimeInterval(1) }).pushOutbound()
        try storeA.delete(id: take.id)   // tombstone deletedAt ≈ real now
        try makeEngine(store: storeA, cloud: cloud, keys: k, now: Date.init).pushOutbound()

        // Device B edited the same Take AFTER the deletion timestamp.
        let storeB = InMemoryTakeStore()
        var edited = take
        edited.bodyText = "edited after the delete"
        edited.modifiedAt = Date().addingTimeInterval(3600)   // strictly after deletedAt
        try storeB.upsert(edited)

        let report = try makeEngine(store: storeB, cloud: cloud, keys: k, now: Date.init).pullInbound()
        XCTAssertTrue(report.deletedLocally.isEmpty, "edit made after deletion must survive")
        XCTAssertEqual(try storeB.take(id: take.id)?.bodyText, "edited after the delete")
    }

    /// `upsert` clears a pending tombstone for the same id — re-creating an item
    /// supersedes its deletion record.
    func testTakeStore_upsertAfterDelete_clearsPendingTombstone() throws {
        let store = InMemoryTakeStore()
        let take = TestFixtures.richTake()
        try store.upsert(take)
        try store.delete(id: take.id)
        XCTAssertEqual(try store.tombstones().map(\.id), [take.id])

        try store.upsert(take)
        XCTAssertTrue(try store.tombstones().isEmpty,
                      "re-creating an item must supersede its pending tombstone")
    }

    // MARK: - Push: watermark semantics (2026-06-10)

    /// The lastSync watermark is captured BEFORE the changed-Takes query and
    /// persisted as-is — not sampled again after the uploads finish. With an
    /// injected constant clock the persisted watermark equals that constant.
    func testSyncEngine_pushWatermark_isPreQueryTimestamp() throws {
        let k = makeKeys()
        let store = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        try store.upsert(TestFixtures.richTake())

        let frozen = Date(timeIntervalSince1970: 1_700_000_000)
        try makeEngine(store: store, cloud: cloud, keys: k, now: { frozen }).pushOutbound()
        XCTAssertEqual(store.lastSyncDate(), frozen,
                       "watermark must be the pre-query `now()`, not a post-I/O resample")
    }

    // MARK: - sync(): lock contention defers the push, never throws

    /// `sync()` no longer surfaces SyncLockError from the push half — the pull
    /// results stand and `pushDeferred` is set.
    func testSync_lockHeldByOtherDevice_setsPushDeferredInsteadOfThrowing() throws {
        let k = makeKeys()
        let cloud = InMemoryCloudFolder()
        let nowDate = Date(timeIntervalSince1970: 1_700_000_000)

        // Remote content to pull.
        let remoteStore = InMemoryTakeStore()
        let take = TestFixtures.richTake()
        try remoteStore.upsert(take)
        try makeEngine(store: remoteStore, cloud: cloud, keys: k, now: { nowDate }).pushOutbound()

        // A FRESH lock owned by another device.
        let otherDevice = UUID()
        let lock = SyncLock(deviceId: otherDevice, acquiredAt: ISO8601.string(from: nowDate))
        try cloud.write(try PlatformJSON.encode(lock), to: SyncLock.fileName)

        let local = InMemoryTakeStore()
        let report = try makeEngine(store: local, cloud: cloud, keys: k,
                                    now: { nowDate.addingTimeInterval(30) }).sync()
        XCTAssertTrue(report.pushDeferred, "lock contention is a routine, reported outcome")
        XCTAssertEqual(report.applied, [take.id], "the pull half's results remain valid")
        XCTAssertTrue(report.uploaded.isEmpty)
    }

    // MARK: - Manifest forward-compat + v1 parse compatibility

    /// A manifest declaring version 3 (signed correctly, so it gets past the
    /// signature check shape) is rejected with `unsupportedManifestVersion`.
    func testPullInbound_manifestVersion3_throwsUnsupportedManifestVersion() throws {
        let k = makeKeys()
        let cloud = InMemoryCloudFolder()
        let signer = ManifestSigner(keys: k)

        var manifest = Manifest(updated: "2026-06-10T00:00:00.000Z", takes: [])
        manifest.version = 3   // set BEFORE signing — version is part of the signed body
        let signed = try signer.sign(manifest)
        try cloud.write(try signed.serialise(), to: Manifest.fileName)

        let engine = makeEngine(store: InMemoryTakeStore(), cloud: cloud, keys: k)
        XCTAssertThrowsError(try engine.pullInbound()) { error in
            XCTAssertEqual(error as? SyncError, .unsupportedManifestVersion(3))
        }
    }

    /// A v1-style manifest JSON without a `tombstones` field still parses,
    /// decoding `tombstones == []`.
    func testManifest_v1JSONWithoutTombstonesField_parsesWithEmptyTombstones() throws {
        let json = """
        {"manifestHmac":"","schemaVersion":1,"takes":[],"updated":"2026-05-28T07:00:00.000Z","version":1}
        """
        let manifest = try Manifest.parse(Data(json.utf8))
        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.tombstones, [])
    }

    /// With EMPTY tombstones the canonical signed bytes contain no `tombstones`
    /// key at all — byte-identical to the pre-v2 format, so old signatures and
    /// other clients keep verifying.
    func testManifest_emptyTombstones_omittedFromCanonicalBytes() throws {
        let manifest = Manifest(updated: "2026-05-28T07:00:00.000Z", takes: [], tombstones: [])
        let bytes = try manifest.bodyForSigning().serialise()
        let json = String(data: bytes, encoding: .utf8)!
        XCTAssertFalse(json.contains("tombstones"), "empty tombstones must be omitted: \(json)")

        var withTombstone = manifest
        withTombstone.tombstones = [ManifestTombstone(uuid: UUID(), deletedAt: "2026-05-28T07:00:00.000Z")]
        let json2 = String(data: try withTombstone.bodyForSigning().serialise(), encoding: .utf8)!
        XCTAssertTrue(json2.contains("tombstones"), "non-empty tombstones must be encoded")
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

    /// A blob declared in the manifest but missing from the folder is SKIPPED
    /// (provider propagation lag — retried next pass), NOT quarantined: it is no
    /// integrity failure. The rest of the pull continues normally.
    func testSyncEngine_missingBlobIsSkippedNotQuarantined() throws {
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

        XCTAssertEqual(report.skipped, [lose.id], "missing blob is skipped, not quarantined")
        XCTAssertTrue(report.quarantined.isEmpty)
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
    /// content differs — the bookkeeping is confused (clock skew / watermark
    /// drift). As of 2026-06-10 this surfaces as a CONFLICT instead of the old
    /// silent most-recent-write fallback: "never silently discards a user's edit".
    func testConflictResolver_bothUnchangedButDiffering_returnsConflict() {
        let lastSync = Date(timeIntervalSince1970: 1_700_000_000)
        var local = TestFixtures.richTake()
        local.bodyText = "local"
        local.modifiedAt = lastSync.addingTimeInterval(-10)  // before watermark
        var remote = local
        remote.bodyText = "remote"
        // Same modifiedAt, both before lastSync — yet the content differs.

        guard case .conflict(let l, let r) = ConflictResolver.decide(local: local, remote: remote, lastSync: lastSync) else {
            return XCTFail("expected .conflict for the (false,false)-but-differing branch")
        }
        XCTAssertEqual(l.bodyText, "local")
        XCTAssertEqual(r.bodyText, "remote")
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
