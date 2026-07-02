//
//  SyncSelfHealAndVersionGuardTests.swift
//  CatchlightCoreTests — 2026-07-01 mid-point review remediation
//
//  Pins three sync-seam fixes:
//
//    1. LONG-OFFLINE HOLD-BACK — a device that hasn't synced within the
//       tombstone-retention window must NOT self-heal-upload Takes it hasn't
//       touched since its last sync: their tombstones may have been pruned, so
//       auto-uploading could resurrect fleet-wide deletions. Held-back ids are
//       reported via `SyncReport.heldBack`; an edit re-asserts the Take.
//    2. CLOUDBLOB FORWARD-COMPAT — a `.clk` envelope with a version newer than
//       this client understands is quarantined, not misread as v1 (the manifest
//       has had the equivalent guard both directions from the start).
//    3. ORPHANED BLOB CLEANUP — when a merged remote tombstone supersedes a
//       manifest entry during push, the blob file is deleted too (previously
//       only LOCAL tombstones deleted blobs, leaving permanent encrypted litter).
//

import XCTest
import CryptoKit
@testable import CatchlightCore

final class SyncSelfHealAndVersionGuardTests: XCTestCase {

    private func keys() -> KeyHierarchy { KeyHierarchy(masterKey: SymmetricKey(size: .bits256)) }

    // MARK: - Long-offline hold-back

    /// Recently-synced device: the self-heal step uploads an unmatched Take
    /// exactly as before — the guard must not change the healthy path.
    func testSelfHeal_uploadsUnmatchedTake_whenRecentlySynced() throws {
        let k = keys()
        let store = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        let take = TestFixtures.richTake()             // modifiedAt 2026-05-02
        try store.upsert(take)
        let now = ISO8601.date(from: "2026-06-01T12:00:00.000Z")!
        store.setLastSyncDate(now.addingTimeInterval(-3600))   // synced an hour ago

        let report = try TestFixtures.engine(store: store, cloud: cloud, keys: k,
                                             now: { now }).pushOutbound()

        XCTAssertEqual(report.uploaded, [take.id])
        XCTAssertTrue(report.heldBack.isEmpty)
        XCTAssertNotNil(try cloud.read("\(take.id.uuidString).clk"))
    }

    /// Device away longer than the retention window: an unmatched Take NOT
    /// modified since its last sync is held back, not uploaded — its deletion
    /// elsewhere can no longer be ruled out.
    func testSelfHeal_holdsBackStaleTake_whenOfflinePastRetention() throws {
        let k = keys()
        let store = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        let take = TestFixtures.richTake()             // modifiedAt 2026-05-02
        try store.upsert(take)
        let lastSync = ISO8601.date(from: "2026-05-03T00:00:00.000Z")!
        store.setLastSyncDate(lastSync)
        let now = lastSync.addingTimeInterval(Manifest.tombstoneRetention + 24 * 3600)

        let report = try TestFixtures.engine(store: store, cloud: cloud, keys: k,
                                             now: { now }).pushOutbound()

        XCTAssertEqual(report.heldBack, [take.id])
        XCTAssertTrue(report.uploaded.isEmpty)
        XCTAssertNil(try cloud.read("\(take.id.uuidString).clk"),
                     "a held-back Take must not be uploaded")
        let manifest = try Manifest.parse(XCTUnwrap(try cloud.read(Manifest.fileName)))
        XCTAssertFalse(manifest.takes.contains { $0.uuid == take.id })
    }

    /// Edit-wins: a Take modified since last sync is uploaded via the normal
    /// changed-Takes path even on a long-offline device — never held back.
    func testSelfHeal_neverHoldsBackTakeEditedSinceLastSync() throws {
        let k = keys()
        let store = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        let lastSync = ISO8601.date(from: "2026-01-01T00:00:00.000Z")!
        let now = lastSync.addingTimeInterval(Manifest.tombstoneRetention + 24 * 3600)
        var take = TestFixtures.richTake()
        take.modifiedAt = now.addingTimeInterval(-60)   // edited a minute ago
        try store.upsert(take)
        store.setLastSyncDate(lastSync)

        let report = try TestFixtures.engine(store: store, cloud: cloud, keys: k,
                                             now: { now }).pushOutbound()

        XCTAssertEqual(report.uploaded, [take.id])
        XCTAssertTrue(report.heldBack.isEmpty)
        XCTAssertNotNil(try cloud.read("\(take.id.uuidString).clk"))
    }

    /// A never-synced store (lastSync nil) is a first bootstrap, not a stale
    /// device — everything uploads.
    func testSelfHeal_firstBootstrap_uploadsEverything() throws {
        let k = keys()
        let store = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        let take = TestFixtures.richTake()
        try store.upsert(take)

        let report = try TestFixtures.engine(store: store, cloud: cloud, keys: k).pushOutbound()

        XCTAssertEqual(report.uploaded, [take.id])
        XCTAssertTrue(report.heldBack.isEmpty)
    }

    // MARK: - CloudBlob forward-compat guard

    /// A validly-HMAC'd envelope carrying a FUTURE version number is quarantined
    /// on pull rather than misread as v1. (Retried naturally once the client is
    /// updated — quarantine is per-pass, not persisted.)
    func testPull_quarantinesFutureVersionBlob() throws {
        let k = keys()
        let cloud = InMemoryCloudFolder()

        // Device B uploads a Take normally…
        let storeB = InMemoryTakeStore()
        let take = TestFixtures.richTake()
        try storeB.upsert(take)
        try TestFixtures.engine(store: storeB, cloud: cloud, keys: k).pushOutbound()

        // …then the blob is rewritten as a future-version envelope with the SAME
        // valid payload, and the manifest re-signed over the new blob HMAC — so
        // the ONLY thing wrong with it is the version number.
        let blobName = "\(take.id.uuidString).clk"
        let original = try CloudBlob.parse(XCTUnwrap(try cloud.read(blobName)))
        let future = CloudBlob(version: CloudBlob.supportedVersions.upperBound + 1,
                               uuid: original.uuid,
                               modified: original.modified,
                               encryptedPayload: original.encryptedPayload)
        let futureBytes = try future.serialise()
        try cloud.write(futureBytes, to: blobName)

        let signer = ManifestSigner(keys: k)
        var manifest = try Manifest.parse(XCTUnwrap(try cloud.read(Manifest.fileName)))
        manifest.takes = manifest.takes.map { entry in
            entry.uuid == take.id
                ? ManifestEntry(uuid: entry.uuid, modified: entry.modified,
                                hmac: signer.blobHMACHex(futureBytes))
                : entry
        }
        let resigned = try signer.sign(manifest.bodyForSigning())
        try cloud.writeAtomically(try resigned.serialise(), to: Manifest.fileName)

        // Device A pulls: the future blob must be quarantined, nothing applied.
        let storeA = InMemoryTakeStore()
        let report = try TestFixtures.engine(store: storeA, cloud: cloud, keys: k).pullInbound()

        XCTAssertEqual(report.quarantined, [take.id])
        XCTAssertTrue(report.applied.isEmpty)
        XCTAssertNil(try storeA.take(id: take.id))
    }

    // MARK: - Orphaned blob cleanup

    /// Push uploads a locally-edited Take, then the same pass merges a NEWER
    /// remote tombstone for it: the entry is dropped from the manifest AND the
    /// just-written blob is deleted — previously it survived as permanent litter.
    func testPush_deletesBlobSupersededByRemoteTombstone() throws {
        let k = keys()
        let cloud = InMemoryCloudFolder()

        // Device B uploads the Take, then deletes it and pushes the tombstone.
        let storeB = InMemoryTakeStore()
        let take = TestFixtures.richTake()             // modifiedAt 2026-05-02
        try storeB.upsert(take)
        let engineB = TestFixtures.engine(store: storeB, cloud: cloud, keys: k)
        try engineB.pushOutbound()
        try storeB.delete(id: take.id)
        try engineB.pushOutbound()
        XCTAssertNil(try cloud.read("\(take.id.uuidString).clk"),
                     "precondition: B's local-tombstone push deletes the blob")

        // Device A never pulled the deletion and still holds the Take live
        // (modified BEFORE the deletion, so the tombstone wins). Its push
        // re-uploads the blob in step 1, then the merged remote tombstone
        // supersedes it in step 3 — the blob must not be left behind.
        let storeA = InMemoryTakeStore()
        try storeA.upsert(take)
        let reportA = try TestFixtures.engine(store: storeA, cloud: cloud, keys: k).pushOutbound()

        XCTAssertTrue(reportA.uploaded.contains(take.id),
                      "step 1 legitimately uploads before the tombstone is resolved")
        XCTAssertNil(try cloud.read("\(take.id.uuidString).clk"),
                     "the superseded blob must be deleted, not orphaned")
        let manifest = try Manifest.parse(XCTUnwrap(try cloud.read(Manifest.fileName)))
        XCTAssertFalse(manifest.takes.contains { $0.uuid == take.id })
        XCTAssertTrue(manifest.tombstones.contains { $0.uuid == take.id })
    }
}
