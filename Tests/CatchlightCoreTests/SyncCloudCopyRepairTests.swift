//
//  SyncCloudCopyRepairTests.swift
//  CatchlightCoreTests
//
//  A cloud copy whose bytes no longer match the manifest's HMAC. The usual cause is a provider
//  keeping an older file after two writes to the same path collided. Before this, such a Take
//  was quarantined on every pull and never repaired unless the user happened to edit it. The
//  owner's rules (2026-09-30):
//
//    1. local version == the manifest entry's version → re-upload local on the same sync,
//       silently (diagnostics only). Never a notice.
//    2. manifest names a NEWER version than local → surfaced for the user to decide, with the
//       cloud copy shown when it still decrypts and marked as unverified.
//    3. not on this device → offered for recovery when it decrypts; otherwise the notice.
//    Plus: a local edit newer than the entry is uploaded by push anyway (no notice), a pending
//    local deletion is never offered back, and a future-version envelope stays quarantined.
//

import XCTest
import CryptoKit
@testable import CatchlightCore

final class SyncCloudCopyRepairTests: XCTestCase {

    private let k = KeyHierarchy(masterKey: SymmetricKey(size: .bits256))
    private let t0 = ISO8601.date(from: "2026-06-01T12:00:00.000Z")!

    private func engine(_ store: TakeStore, _ cloud: CloudFolder, at now: Date) -> SyncEngine {
        TestFixtures.engine(store: store, cloud: cloud, keys: k, now: { now })
    }

    private func version(_ base: Take, _ text: String, at date: Date) -> Take {
        var t = base
        t.blocks = [.textLine(text)]
        t.modifiedAt = date
        return t
    }

    private func blobName(_ id: UUID) -> String { "\(id.uuidString).clk" }

    /// Push `take` from a fresh device so the cloud holds it; returns that device's store.
    @discardableResult
    private func pushFromDevice(_ take: Take, to cloud: CloudFolder, at now: Date) throws -> InMemoryTakeStore {
        let store = InMemoryTakeStore()
        try store.upsert(take)
        store.setLastSyncDate(take.modifiedAt.addingTimeInterval(-60))
        try engine(store, cloud, at: now).pushOutbound()
        return store
    }

    // MARK: - 1. Same version: repaired on the same sync, silently

    func testSameVersion_mismatchedCopy_isRepairedOnTheSameSync_withNoNotice() throws {
        let cloud = InMemoryCloudFolder()
        let v1 = version(TestFixtures.richTake(), "first", at: t0)
        let phone = try pushFromDevice(v1, to: cloud, at: t0)
        let staleBytes = try XCTUnwrap(try cloud.read(blobName(v1.id)))
        // The same version sealed again (fresh nonce), so the manifest HMAC moves on...
        try pushFromDevice(v1, to: cloud, at: t0.addingTimeInterval(60))
        // ...and the provider keeps the earlier file at the canonical path.
        try cloud.write(staleBytes, to: blobName(v1.id))
        phone.setLastSyncDate(t0.addingTimeInterval(120))

        let report = try engine(phone, cloud, at: t0.addingTimeInterval(180)).sync()

        XCTAssertTrue(report.quarantined.isEmpty, "a repairable copy must not raise the notice")
        XCTAssertTrue(report.unverified.isEmpty, "nothing for the user to decide")
        XCTAssertEqual(report.repaired, [v1.id])
        let after = try engine(phone, cloud, at: t0.addingTimeInterval(240)).pullInbound()
        XCTAssertTrue(after.quarantined.isEmpty && after.unverified.isEmpty && after.repaired.isEmpty,
                      "the next pull verifies cleanly")
    }

    // MARK: - 2. Manifest names a newer version than this device holds

    func testNewerInManifest_readableStaleCopy_isSurfacedWithBothVersions() throws {
        let cloud = InMemoryCloudFolder()
        let v1 = version(TestFixtures.richTake(), "first", at: t0)
        let phone = try pushFromDevice(v1, to: cloud, at: t0)
        let v1Bytes = try XCTUnwrap(try cloud.read(blobName(v1.id)))
        let v2 = version(v1, "second, from another device", at: t0.addingTimeInterval(600))
        try pushFromDevice(v2, to: cloud, at: t0.addingTimeInterval(600))
        try cloud.write(v1Bytes, to: blobName(v1.id))   // the newer file was lost
        phone.setLastSyncDate(t0.addingTimeInterval(60))

        let report = try engine(phone, cloud, at: t0.addingTimeInterval(900)).pullInbound()

        XCTAssertTrue(report.quarantined.isEmpty)
        XCTAssertTrue(report.repaired.isEmpty, "never overwrite a newer version named by the manifest")
        let item = try XCTUnwrap(report.unverified.first)
        XCTAssertEqual(item.id, v1.id)
        XCTAssertEqual(item.local, v1)
        XCTAssertEqual(item.cloud?.blocks, v1.blocks, "the copy that decrypted is shown, marked unverified")
        XCTAssertEqual(try phone.take(id: v1.id), v1, "pull never writes an unverified copy locally")
    }

    func testNewerInManifest_unreadableCopy_isSurfacedWithoutACloudVersion() throws {
        let cloud = InMemoryCloudFolder()
        let v1 = version(TestFixtures.richTake(), "first", at: t0)
        let phone = try pushFromDevice(v1, to: cloud, at: t0)
        try pushFromDevice(version(v1, "second", at: t0.addingTimeInterval(600)), to: cloud,
                           at: t0.addingTimeInterval(600))
        try cloud.write(Data("not a blob".utf8), to: blobName(v1.id))
        phone.setLastSyncDate(t0.addingTimeInterval(60))

        let report = try engine(phone, cloud, at: t0.addingTimeInterval(900)).pullInbound()

        let item = try XCTUnwrap(report.unverified.first)
        XCTAssertEqual(item.local, v1)
        XCTAssertNil(item.cloud, "nothing readable to show")
        XCTAssertTrue(report.quarantined.isEmpty, "it goes to the user, not the notice")
    }

    // MARK: - 3. Not on this device

    func testNotOnDevice_readableCopy_isOfferedForRecovery() throws {
        let cloud = InMemoryCloudFolder()
        let v1 = version(TestFixtures.richTake(), "first", at: t0)
        try pushFromDevice(v1, to: cloud, at: t0)
        let v1Bytes = try XCTUnwrap(try cloud.read(blobName(v1.id)))
        try pushFromDevice(version(v1, "second", at: t0.addingTimeInterval(600)), to: cloud,
                           at: t0.addingTimeInterval(600))
        try cloud.write(v1Bytes, to: blobName(v1.id))
        let fresh = InMemoryTakeStore()

        let report = try engine(fresh, cloud, at: t0.addingTimeInterval(900)).pullInbound()

        let item = try XCTUnwrap(report.unverified.first)
        XCTAssertNil(item.local)
        XCTAssertEqual(item.cloud?.blocks, v1.blocks)
        XCTAssertNil(try fresh.take(id: v1.id), "recovery is the user's choice, never automatic")
    }

    func testNotOnDevice_unreadableCopy_staysQuarantined() throws {
        let cloud = InMemoryCloudFolder()
        let v1 = version(TestFixtures.richTake(), "first", at: t0)
        try pushFromDevice(v1, to: cloud, at: t0)
        try cloud.write(Data("not a blob".utf8), to: blobName(v1.id))

        let report = try engine(InMemoryTakeStore(), cloud, at: t0.addingTimeInterval(900)).pullInbound()

        XCTAssertEqual(report.quarantined, [v1.id])
        XCTAssertTrue(report.unverified.isEmpty)
    }

    // MARK: - Guards

    func testPendingLocalDeletion_isNeverOfferedBack() throws {
        let cloud = InMemoryCloudFolder()
        let v1 = version(TestFixtures.richTake(), "first", at: t0)
        let phone = try pushFromDevice(v1, to: cloud, at: t0)
        let v1Bytes = try XCTUnwrap(try cloud.read(blobName(v1.id)))
        try pushFromDevice(v1, to: cloud, at: t0.addingTimeInterval(60))
        try cloud.write(v1Bytes, to: blobName(v1.id))
        try phone.delete(id: v1.id)   // deleted here, not yet pushed

        let report = try engine(phone, cloud, at: t0.addingTimeInterval(900)).pullInbound()

        XCTAssertTrue(report.unverified.isEmpty && report.quarantined.isEmpty && report.repaired.isEmpty)
    }

    func testLocalEditNewerThanManifest_isUploadedWithNoNotice() throws {
        let cloud = InMemoryCloudFolder()
        let v1 = version(TestFixtures.richTake(), "first", at: t0)
        let phone = try pushFromDevice(v1, to: cloud, at: t0)
        let staleBytes = try XCTUnwrap(try cloud.read(blobName(v1.id)))
        try pushFromDevice(v1, to: cloud, at: t0.addingTimeInterval(60))
        try cloud.write(staleBytes, to: blobName(v1.id))
        phone.setLastSyncDate(t0.addingTimeInterval(120))
        let v3 = version(v1, "edited here since", at: t0.addingTimeInterval(300))
        try phone.upsert(v3)

        let report = try engine(phone, cloud, at: t0.addingTimeInterval(400)).sync()

        XCTAssertTrue(report.quarantined.isEmpty && report.unverified.isEmpty)
        XCTAssertTrue(report.uploaded.contains(v1.id))
        let after = try engine(InMemoryTakeStore(), cloud, at: t0.addingTimeInterval(500)).pullInbound()
        XCTAssertEqual(after.applied, [v1.id], "the edit reached the cloud and verifies")
    }
}
