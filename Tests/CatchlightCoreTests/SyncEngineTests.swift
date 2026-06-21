//
//  SyncEngineTests.swift
//  CatchlightCoreTests
//
//  Phase 5 brief §12.4 — sync engine. Plus manifest signing/verification (§7.3)
//  and conflict detection (§7.6). All tests use the in-memory cloud folder — no
//  file system, no network.
//

import XCTest
import CryptoKit
@testable import CatchlightCore

final class SyncEngineTests: XCTestCase {

    private func keys() -> KeyHierarchy { KeyHierarchy(masterKey: SymmetricKey(size: .bits256)) }

    private func makeEngine(store: TakeStore, cloud: CloudFolder?, keys: KeyHierarchy, now: @escaping () -> Date = Date.init) -> SyncEngine {
        TestFixtures.engine(store: store, cloud: cloud, keys: keys, now: now)
    }

    // Outbound writes envelopes + a signed manifest + the plaintext metadata file.
    func testOutboundWritesEnvelopesAndManifest() throws {
        let k = keys()
        let store = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        let take = TestFixtures.richTake()
        try store.upsert(take)

        let engine = makeEngine(store: store, cloud: cloud, keys: k)
        try engine.pushOutbound()

        XCTAssertNotNil(try cloud.read("\(take.id.uuidString).clk"))
        XCTAssertNotNil(try cloud.read(Manifest.fileName))
        XCTAssertNotNil(try cloud.read("catchlight-account-metadata.json"))

        // The .clk envelope is the platform-agnostic JSON form, not binary.
        let blobData = try cloud.read(take.fileNameForTest)!
        let blob = try CloudBlob.parse(blobData)
        XCTAssertEqual(blob.uuid, take.id)
        XCTAssertEqual(blob.version, 1)
        XCTAssertNotNil(blob.ciphertext)
    }

    // §12.4 — Manifest HMAC verification fails on any modification to a Take blob.
    func testManifestDetectsBlobTampering() throws {
        let k = keys()
        let store = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        let take = TestFixtures.richTake()
        try store.upsert(take)
        try makeEngine(store: store, cloud: cloud, keys: k).pushOutbound()

        // Tamper with a blob.
        var blob = try cloud.read("\(take.id.uuidString).clk")!
        blob[blob.count - 1] ^= 0xFF
        try cloud.write(blob, to: "\(take.id.uuidString).clk")

        // A fresh device pulling should quarantine that Take (per-blob HMAC fails).
        let store2 = InMemoryTakeStore()
        let report = try makeEngine(store: store2, cloud: cloud, keys: k).pullInbound()
        XCTAssertEqual(report.quarantined, [take.id])
        XCTAssertTrue(report.applied.isEmpty)
        XCTAssertNil(try store2.take(id: take.id), "tampered Take never written to local DB")
    }

    // §12.4 — Manifest verification failure quarantines remote changes and does not
    // modify the local database.
    func testManifestSignatureFailureLeavesLocalUntouched() throws {
        let k = keys()
        let store = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        try store.upsert(TestFixtures.richTake())
        try makeEngine(store: store, cloud: cloud, keys: k).pushOutbound()

        // Tamper with the manifest body so its own HMAC no longer verifies.
        var manifest = try Manifest.parse(try cloud.read(Manifest.fileName)!)
        manifest.updated = "1999-01-01T00:00:00.000Z"
        try cloud.write(try manifest.serialise(), to: Manifest.fileName)

        let store2 = InMemoryTakeStore()
        let existing = TestFixtures.richTake(id: UUID())
        try store2.upsert(existing)
        let engine = makeEngine(store: store2, cloud: cloud, keys: k)
        XCTAssertThrowsError(try engine.pullInbound()) { error in
            XCTAssertEqual(error as? SyncError, .manifestSignatureInvalid)
        }
        // Local DB untouched.
        XCTAssertEqual(try store2.allTakes().map(\.id), [existing.id])
    }

    // A wrong master key (different manifest HMAC key) also fails verification.
    func testManifestSignatureFailsUnderWrongKey() throws {
        let store = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        try store.upsert(TestFixtures.richTake())
        try makeEngine(store: store, cloud: cloud, keys: keys()).pushOutbound()

        let attackerKeys = keys()  // different master key
        let store2 = InMemoryTakeStore()
        XCTAssertThrowsError(try makeEngine(store: store2, cloud: cloud, keys: attackerKeys).pullInbound()) { error in
            XCTAssertEqual(error as? SyncError, .manifestSignatureInvalid)
        }
    }

    // §12.4 — Inbound sync correctly handles a NEW Take from another device.
    func testInboundNewTakeFromAnotherDevice() throws {
        let k = keys()
        // Device A creates and pushes.
        let storeA = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        let take = TestFixtures.richTake()
        try storeA.upsert(take)
        try makeEngine(store: storeA, cloud: cloud, keys: k).pushOutbound()

        // Device B (empty) pulls.
        let storeB = InMemoryTakeStore()
        let report = try makeEngine(store: storeB, cloud: cloud, keys: k).pullInbound()
        XCTAssertEqual(report.applied, [take.id])
        XCTAssertEqual(try storeB.take(id: take.id), take)
    }

    // §12.4 — Inbound sync correctly handles a DELETED Take from another device.
    func testInboundDeletionFromAnotherDevice() throws {
        let k = keys()
        let cloud = InMemoryCloudFolder()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        // Device A pushes one Take.
        let storeA = InMemoryTakeStore()
        var take = TestFixtures.richTake()
        take.modifiedAt = t0
        try storeA.upsert(take)
        try makeEngine(store: storeA, cloud: cloud, keys: k, now: { t0.addingTimeInterval(1) }).pushOutbound()

        // Device B pulls it (so it's part of B's synced baseline).
        let storeB = InMemoryTakeStore()
        try makeEngine(store: storeB, cloud: cloud, keys: k, now: { t0.addingTimeInterval(2) }).pullInbound()
        // B's last-sync watermark must be after the Take's modifiedAt for it to be
        // considered "previously synced, unchanged locally".
        storeB.setLastSyncDate(t0.addingTimeInterval(5))
        XCTAssertNotNil(try storeB.take(id: take.id))

        // Device A deletes the Take and pushes (removes blob, records a manifest
        // tombstone — explicit-deletion model, 2026-06-10).
        try storeA.delete(id: take.id)
        try makeEngine(store: storeA, cloud: cloud, keys: k, now: { t0.addingTimeInterval(10) }).pushOutbound()

        // Device B pulls → applies the remote deletion locally.
        let report = try makeEngine(store: storeB, cloud: cloud, keys: k, now: { t0.addingTimeInterval(11) }).pullInbound()
        XCTAssertEqual(report.deletedLocally, [take.id])
        XCTAssertNil(try storeB.take(id: take.id))
    }

    // A locally-created Take not yet pushed is NOT deleted by an inbound pull.
    func testInboundDoesNotDeleteLocallyPendingTake() throws {
        let k = keys()
        let cloud = InMemoryCloudFolder()
        // Remote has Take X; local has X (synced) + Y (new, pending upload).
        let storeRemote = InMemoryTakeStore()
        let x = TestFixtures.richTake(id: UUID())
        try storeRemote.upsert(x)
        try makeEngine(store: storeRemote, cloud: cloud, keys: k).pushOutbound()

        let local = InMemoryTakeStore()
        try local.upsert(x)
        local.setLastSyncDate(Date())          // X considered already synced
        var y = TestFixtures.richTake(id: UUID())
        y.modifiedAt = Date().addingTimeInterval(60)   // newer than watermark → pending
        try local.upsert(y)

        let report = try makeEngine(store: local, cloud: cloud, keys: k).pullInbound()
        XCTAssertFalse(report.deletedLocally.contains(y.id))
        XCTAssertNotNil(try local.take(id: y.id))
    }

    /// REGRESSION (owner-reported 2026-06-21): a Take deleted locally but not yet pushed
    /// must NOT be resurrected by the pull half of the same sync. `sync()` is pull-then-push,
    /// and the cloud manifest still lists the Take with no tombstone — without the guard,
    /// `ConflictResolver` reads `local == nil` as "new from another device" and re-creates
    /// it, the re-creating `upsert` clears the pending tombstone, and the deletion can never
    /// propagate (it silently comes back on every app open).
    func testPull_doesNotResurrectLocallyDeletedTakeNotYetPushed() throws {
        let k = keys()
        let store = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        let take = TestFixtures.richTake()
        try store.upsert(take)
        let engine = makeEngine(store: store, cloud: cloud, keys: k)
        try engine.pushOutbound()                          // cloud now has blob + manifest entry

        // Delete locally — records a pending tombstone; NOT pushed yet.
        try store.delete(id: take.id)
        XCTAssertNil(try store.take(id: take.id))
        XCTAssertEqual(try store.tombstones().map(\.id), [take.id])

        // The next sync pulls FIRST. The deletion must survive, not resurrect.
        let report = try engine.pullInbound()
        XCTAssertNil(try store.take(id: take.id),
                     "a not-yet-pushed deletion must not be resurrected by pull")
        XCTAssertFalse(report.applied.contains(take.id))
        XCTAssertEqual(try store.tombstones().map(\.id), [take.id],
                       "the pending tombstone survives the pull so push can propagate it")

        // The push half then propagates the deletion end-to-end.
        try engine.pushOutbound()
        let manifest = try Manifest.parse(try XCTUnwrap(cloud.read(Manifest.fileName)))
        XCTAssertTrue(manifest.tombstones.contains { $0.uuid == take.id }, "manifest records the tombstone")
        XCTAssertFalse(manifest.takes.contains { $0.uuid == take.id }, "manifest no longer lists the Take")
        XCTAssertNil(try cloud.read("\(take.id.uuidString).clk"), "the blob is deleted")
    }

    /// Edit-wins is preserved: if ANOTHER device edits the Take strictly AFTER our local
    /// deletion, that remote edit still resurrects it on pull (the guard only suppresses
    /// resurrection while our deletion is the most-recent event).
    func testPull_remoteEditAfterLocalDeletion_stillResurrects_editWins() throws {
        let k = keys()
        let cloud = InMemoryCloudFolder()
        let deviceA = UUID(), deviceB = UUID()
        let take = TestFixtures.richTake()

        // A creates + pushes; B pulls it into its baseline.
        let storeA = InMemoryTakeStore()
        try storeA.upsert(take)
        try TestFixtures.engine(store: storeA, cloud: cloud, keys: k, deviceId: deviceA).pushOutbound()
        let storeB = InMemoryTakeStore()
        try TestFixtures.engine(store: storeB, cloud: cloud, keys: k, deviceId: deviceB).pullInbound()

        // A deletes locally (not pushed). B edits the SAME Take strictly later and pushes.
        try storeA.delete(id: take.id)
        var edited = try XCTUnwrap(storeB.take(id: take.id))
        edited.modifiedAt = Date().addingTimeInterval(3600)     // after A's deletion
        edited.blocks = [.textLine("edited on B after A deleted it")]
        try storeB.upsert(edited)
        try TestFixtures.engine(store: storeB, cloud: cloud, keys: k, deviceId: deviceB).pushOutbound()

        // A pulls: the remote edit is newer than A's deletion → edit wins, Take resurrects.
        try TestFixtures.engine(store: storeA, cloud: cloud, keys: k, deviceId: deviceA).pullInbound()
        XCTAssertNotNil(try storeA.take(id: take.id),
                        "a remote edit made after the local deletion wins (resurrects)")
    }

    // §12.4 — Conflict detection: two offline edits to the same Take.
    func testConflictDetection() throws {
        let lastSync = Date(timeIntervalSince1970: 1_700_000_000)
        var base = TestFixtures.richTake()
        base.modifiedAt = lastSync

        var localEdit = base
        localEdit.primaryText = "local edit"
        localEdit.modifiedAt = lastSync.addingTimeInterval(100)

        var remoteEdit = base
        remoteEdit.primaryText = "remote edit"
        remoteEdit.modifiedAt = lastSync.addingTimeInterval(200)

        let decision = ConflictResolver.decide(local: localEdit, remote: remoteEdit, lastSync: lastSync)
        guard case .conflict(let l, let r) = decision else {
            return XCTFail("expected a conflict, got \(decision)")
        }
        XCTAssertEqual(l.primaryText, "local edit")
        XCTAssertEqual(r.primaryText, "remote edit")
    }

    func testOnlyRemoteChangedTakesRemote() {
        let lastSync = Date(timeIntervalSince1970: 1_700_000_000)
        var local = TestFixtures.richTake(); local.modifiedAt = lastSync.addingTimeInterval(-10)
        var remote = local; remote.primaryText = "newer"; remote.modifiedAt = lastSync.addingTimeInterval(50)
        guard case .takeRemote = ConflictResolver.decide(local: local, remote: remote, lastSync: lastSync) else {
            return XCTFail("expected takeRemote")
        }
    }

    func testEndToEndConflictSurfacedDuringInbound() throws {
        let k = keys()
        let cloud = InMemoryCloudFolder()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        // Remote device pushes an edited version.
        let remoteStore = InMemoryTakeStore()
        var remote = TestFixtures.richTake()
        remote.primaryText = "remote version"
        remote.modifiedAt = t0.addingTimeInterval(300)
        try remoteStore.upsert(remote)
        try makeEngine(store: remoteStore, cloud: cloud, keys: k, now: { t0.addingTimeInterval(301) }).pushOutbound()

        // Local device has its own edit since the same baseline.
        let local = InMemoryTakeStore()
        var localEdit = TestFixtures.richTake(id: remote.id)
        localEdit.primaryText = "local version"
        localEdit.modifiedAt = t0.addingTimeInterval(250)
        try local.upsert(localEdit)
        local.setLastSyncDate(t0)   // both edits are after the watermark

        let report = try makeEngine(store: local, cloud: cloud, keys: k, now: { t0.addingTimeInterval(400) }).pullInbound()
        XCTAssertEqual(report.conflicts.count, 1)
        // Local DB is NOT silently overwritten — resolution UI is Phase 6.
        XCTAssertEqual(try local.take(id: remote.id)?.primaryText, "local version")
    }

    // §12.4 — Local-only mode: no file system writes outside the app container.
    func testLocalOnlyModeNoCloudWrites() throws {
        let store = InMemoryTakeStore()
        let engine = makeEngine(store: store, cloud: nil, keys: keys())
        XCTAssertTrue(engine.isLocalOnly)
        try store.upsert(TestFixtures.richTake())   // encryption still works at store level
        XCTAssertThrowsError(try engine.pushOutbound()) { error in
            XCTAssertEqual(error as? SyncError, .noCloudFolderConfigured)
        }
        XCTAssertThrowsError(try engine.pullInbound()) { error in
            XCTAssertEqual(error as? SyncError, .noCloudFolderConfigured)
        }
    }

    // Local-only → later configures a folder → first push uploads everything (§7.9).
    func testLocalOnlyThenEnableSyncUploadsAll() throws {
        let k = keys()
        let store = InMemoryTakeStore()
        for _ in 0..<3 { try store.upsert(TestFixtures.richTake(id: UUID())) }
        // First run with a folder uploads all pre-existing local Takes.
        let cloud = InMemoryCloudFolder()
        let report = try makeEngine(store: store, cloud: cloud, keys: k).pushOutbound()
        XCTAssertEqual(report.uploaded.count, 3)
        XCTAssertEqual(try cloud.clkFiles().count, 3)
    }

    // Idempotency: pushing twice with no changes is safe and stable.
    func testOutboundIdempotent() throws {
        let k = keys()
        let store = InMemoryTakeStore()
        try store.upsert(TestFixtures.richTake())
        let cloud = InMemoryCloudFolder()
        let engine = makeEngine(store: store, cloud: cloud, keys: k)
        try engine.pushOutbound()
        let firstManifest = try cloud.read(Manifest.fileName)
        try engine.pushOutbound()
        // Manifest still verifies; file set unchanged (1 blob + manifest + metadata).
        let signer = ManifestSigner(keys: k)
        XCTAssertTrue(try signer.verify(Manifest.parse(try cloud.read(Manifest.fileName)!)))
        XCTAssertNotNil(firstManifest)
        XCTAssertEqual(try cloud.clkFiles().count, 1)
    }
}

private extension Take {
    var fileNameForTest: String { "\(id.uuidString).clk" }
}
