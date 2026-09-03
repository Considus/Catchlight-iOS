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
        let manifest = try Manifest.readEncrypted(from: cloud, keys: k)
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
        var manifest = try Manifest.readEncrypted(from: cloud, keys: k)
        manifest.takes = manifest.takes.map { entry in
            entry.uuid == take.id
                ? ManifestEntry(uuid: entry.uuid, modified: entry.modified,
                                hmac: signer.blobHMACHex(futureBytes))
                : entry
        }
        // v3 (D-196): re-seal as well as re-sign, so the engine still reads an encrypted
        // manifest and the ONLY thing wrong with the folder is the blob's version number.
        let resigned = try signer.sign(try manifest.sealed(with: k.manifestEncryptionKey()))
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
        let manifest = try Manifest.readEncrypted(from: cloud, keys: k)
        XCTAssertFalse(manifest.takes.contains { $0.uuid == take.id })
        XCTAssertTrue(manifest.tombstones.contains { $0.uuid == take.id })
    }

    // MARK: - Stale manifest entry (2026-09-03, D-250)

    /// THE REPRODUCTION. A Take whose cloud copy is STALE — the manifest entry
    /// records an older `modified` than the local Take carries — must be re-uploaded,
    /// even when the last-sync watermark has already advanced past the local change.
    ///
    /// Push selects by `modifiedAt > lastSync` (step 1) and self-heals only Takes with
    /// NO manifest entry (step 4). A Take with an entry AND a `modifiedAt` behind the
    /// watermark is therefore selected by neither, so the stale cloud copy is never
    /// corrected and every subsequent pull re-raises it as a conflict — indefinitely.
    /// Observed on device: conflicts grew 1 → 4 and then stopped clearing across 15
    /// hours and three launches, with `Sync: push ok` immediately before each one.
    func testSelfHeal_reuploadsTake_whenManifestEntryIsStale() throws {
        let k = keys()
        let store = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        let take = TestFixtures.richTake()                     // modifiedAt 2026-05-02
        try store.upsert(take)

        // First push: cloud gains a blob and an entry recording the ORIGINAL modifiedAt.
        let firstPush = ISO8601.date(from: "2026-06-01T12:00:00.000Z")!
        store.setLastSyncDate(firstPush.addingTimeInterval(-3600))
        _ = try TestFixtures.engine(store: store, cloud: cloud, keys: k,
                                    now: { firstPush }).pushOutbound()
        let entryBefore = try Manifest.readEncrypted(from: cloud, keys: k).takes.first { $0.uuid == take.id }
        XCTAssertEqual(entryBefore?.modified, ISO8601.string(from: take.modifiedAt),
                       "precondition: the first push recorded the original modifiedAt")

        // The local Take diverges — its modifiedAt moves on, but the cloud is not updated.
        // (On device this came from a no-op inline save; the cause does not matter here,
        // only that push must converge the cloud to local whatever produced the gap.)
        var diverged = take
        diverged.modifiedAt = firstPush.addingTimeInterval(60)
        try store.upsert(diverged)

        // The watermark then advances PAST the local change, which is what strands it:
        // step 1 will no longer select it and step 4 never looked at entries that exist.
        store.setLastSyncDate(firstPush.addingTimeInterval(600))

        let secondPush = firstPush.addingTimeInterval(1200)
        let report = try TestFixtures.engine(store: store, cloud: cloud, keys: k,
                                             now: { secondPush }).pushOutbound()

        XCTAssertEqual(report.uploaded, [take.id],
            "A Take whose manifest entry is stale must be re-uploaded regardless of the watermark; otherwise the cloud copy is permanently wrong and every pull raises a conflict.")

        let entryAfter = try Manifest.readEncrypted(from: cloud, keys: k).takes.first { $0.uuid == take.id }
        XCTAssertEqual(entryAfter?.modified, ISO8601.string(from: diverged.modifiedAt),
            "The manifest still records the stale modifiedAt — the cloud has not converged on local.")
    }

    /// The healthy path must not become chattier: a Take whose manifest entry already
    /// matches local is NOT re-uploaded, so the fix cannot turn every push into a full
    /// re-upload of the store.
    func testSelfHeal_doesNotReuploadTake_whenManifestEntryMatches() throws {
        let k = keys()
        let store = InMemoryTakeStore()
        let cloud = InMemoryCloudFolder()
        let take = TestFixtures.richTake()
        try store.upsert(take)

        let firstPush = ISO8601.date(from: "2026-06-01T12:00:00.000Z")!
        store.setLastSyncDate(firstPush.addingTimeInterval(-3600))
        _ = try TestFixtures.engine(store: store, cloud: cloud, keys: k,
                                    now: { firstPush }).pushOutbound()

        // Nothing changed locally; the watermark moves on.
        store.setLastSyncDate(firstPush.addingTimeInterval(600))
        let report = try TestFixtures.engine(store: store, cloud: cloud, keys: k,
                                             now: { firstPush.addingTimeInterval(1200) }).pushOutbound()

        XCTAssertTrue(report.uploaded.isEmpty,
            "An unchanged Take was re-uploaded — the staleness check must compare against the manifest entry, not re-upload unconditionally.")
    }
}
