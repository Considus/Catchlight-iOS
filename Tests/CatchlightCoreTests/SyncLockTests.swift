//
//  SyncLockTests.swift
//  CatchlightCoreTests
//
//  Lock-file serialisation around outbound sync (Phase 5 brief §7.10).
//

import XCTest
import CryptoKit
@testable import CatchlightCore

final class SyncLockTests: XCTestCase {

    private let deviceA = UUID()
    private let deviceB = UUID()

    private func makeKeys() -> KeyHierarchy { KeyHierarchy(masterKey: SymmetricKey(size: .bits256)) }

    private func makeEngine(
        store: TakeStore,
        cloud: CloudFolder?,
        deviceId: UUID,
        now: @escaping () -> Date = Date.init
    ) -> SyncEngine {
        TestFixtures.engine(store: store, cloud: cloud, keys: makeKeys(), deviceId: deviceId, now: now)
    }

    /// A fresh lock owned by another device blocks push and surfaces
    /// `SyncLockError.heldByOtherDevice` with the holder's UUID.
    func testFreshLockFromOtherDeviceAbortsPush() throws {
        let cloud = InMemoryCloudFolder()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // Pre-seed a fresh lock owned by device B.
        let other = SyncLock(deviceId: deviceB, acquiredAt: ISO8601.string(from: now))
        try cloud.write(try PlatformJSON.encode(other), to: SyncLock.fileName)

        let engine = makeEngine(store: InMemoryTakeStore(), cloud: cloud, deviceId: deviceA, now: { now.addingTimeInterval(30) })

        XCTAssertThrowsError(try engine.pushOutbound()) { err in
            guard case let SyncLockError.heldByOtherDevice(holder, _) = err else {
                XCTFail("expected heldByOtherDevice, got \(err)"); return
            }
            XCTAssertEqual(holder, self.deviceB)
        }

        // Lock untouched (we didn't own it, didn't release it).
        XCTAssertNotNil(try cloud.read(SyncLock.fileName))
    }

    /// A stale lock (> 5 min) is overwritten and the push proceeds.
    func testStaleLockIsOverwrittenAndPushProceeds() throws {
        let cloud = InMemoryCloudFolder()
        let acquiredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let nowDate = acquiredAt.addingTimeInterval(10 * 60)   // 10 minutes later

        let stale = SyncLock(deviceId: deviceB, acquiredAt: ISO8601.string(from: acquiredAt))
        try cloud.write(try PlatformJSON.encode(stale), to: SyncLock.fileName)

        let store = InMemoryTakeStore()
        try store.upsert(TestFixtures.richTake())
        let engine = makeEngine(store: store, cloud: cloud, deviceId: deviceA, now: { nowDate })

        XCTAssertNoThrow(try engine.pushOutbound())
        // Push completed — defer releases our own lock; nothing left on the folder.
        XCTAssertNil(try cloud.read(SyncLock.fileName))
        // And the push actually happened (manifest written).
        XCTAssertNotNil(try cloud.read(Manifest.fileName))
    }

    /// On a successful push, the lock file is removed by the defer in pushOutbound.
    func testLockReleasedOnSuccessfulPush() throws {
        let cloud = InMemoryCloudFolder()
        let store = InMemoryTakeStore()
        try store.upsert(TestFixtures.richTake())

        let engine = makeEngine(store: store, cloud: cloud, deviceId: deviceA)
        try engine.pushOutbound()

        XCTAssertNil(try cloud.read(SyncLock.fileName), "lock should not survive a successful push")
    }

    /// If push throws AFTER we acquired the lock, the defer must still release it.
    /// We force a throw by deleting the manifest in a wrapping CloudFolder mid-flight.
    func testLockReleasedEvenWhenPushThrows() throws {
        let cloud = ThrowOnManifestWrite(inner: InMemoryCloudFolder())
        let store = InMemoryTakeStore()
        try store.upsert(TestFixtures.richTake())

        let engine = makeEngine(store: store, cloud: cloud, deviceId: deviceA)

        XCTAssertThrowsError(try engine.pushOutbound())
        // The lock was acquired (by us) before the throw — defer must have released it.
        XCTAssertNil(try cloud.read(SyncLock.fileName), "lock must be released on failure path too")
    }

    /// A previously-orphaned lock owned by THIS device is overwritten (no deadlock
    /// after a crash from the same install).
    func testOwnOrphanedLockOverwritten() throws {
        let cloud = InMemoryCloudFolder()
        let acquiredAt = Date(timeIntervalSince1970: 1_700_000_000)
        // Fresh, but owned by us.
        let own = SyncLock(deviceId: deviceA, acquiredAt: ISO8601.string(from: acquiredAt))
        try cloud.write(try PlatformJSON.encode(own), to: SyncLock.fileName)

        let store = InMemoryTakeStore()
        try store.upsert(TestFixtures.richTake())
        let engine = makeEngine(store: store, cloud: cloud, deviceId: deviceA, now: { acquiredAt.addingTimeInterval(10) })

        XCTAssertNoThrow(try engine.pushOutbound())
        XCTAssertNil(try cloud.read(SyncLock.fileName))
    }

    /// Read-back verification (2026-06-10): if another device's lock write lands
    /// in the same window — i.e. the read-back after our write returns THEIR
    /// lock — `acquireLock` backs off with `heldByOtherDevice` rather than
    /// proceeding on a stolen lock.
    func testAcquireLock_readBackShowsOtherDevice_backsOff() throws {
        let other = UUID()
        let cloud = LostWriteCloudFolder(
            winnerLock: SyncLock(deviceId: other, acquiredAt: ISO8601.string(from: Date()))
        )
        let engine = makeEngine(store: InMemoryTakeStore(), cloud: cloud, deviceId: deviceA)

        XCTAssertThrowsError(try engine.acquireLock(on: cloud)) { err in
            guard case let SyncLockError.heldByOtherDevice(holder, _) = err else {
                return XCTFail("expected heldByOtherDevice, got \(err)")
            }
            XCTAssertEqual(holder, other)
        }
    }
}

/// Test double simulating a write race: writes to the lock file are LOST (the
/// other device's write wins), so the post-write read-back returns the winner's
/// lock instead of ours.
private final class LostWriteCloudFolder: CloudFolder {
    private let inner = InMemoryCloudFolder()
    private let winnerLock: SyncLock
    private var lockWritten = false

    init(winnerLock: SyncLock) { self.winnerLock = winnerLock }

    func listFiles() throws -> [String] { try inner.listFiles() }
    func read(_ name: String) throws -> Data? {
        if name == SyncLock.fileName, lockWritten {
            return try PlatformJSON.encode(winnerLock)   // their write won
        }
        return try inner.read(name)
    }
    func write(_ data: Data, to name: String) throws {
        if name == SyncLock.fileName { lockWritten = true; return }   // our write lost
        try inner.write(data, to: name)
    }
    func writeAtomically(_ data: Data, to name: String) throws { try write(data, to: name) }
    func delete(_ name: String) throws { try inner.delete(name) }
}

/// Test double: throws on the manifest atomic write so we can verify lock release
/// on the throw path. All other operations pass through.
private final class ThrowOnManifestWrite: CloudFolder {
    let inner: InMemoryCloudFolder
    init(inner: InMemoryCloudFolder) { self.inner = inner }

    func listFiles() throws -> [String] { try inner.listFiles() }
    func read(_ name: String) throws -> Data? { try inner.read(name) }
    func write(_ data: Data, to name: String) throws { try inner.write(data, to: name) }
    func delete(_ name: String) throws { try inner.delete(name) }
    func secureDelete(_ name: String) throws { try inner.secureDelete(name) }

    func writeAtomically(_ data: Data, to name: String) throws {
        if name == Manifest.fileName {
            throw StorageError.writeFailed("simulated manifest write failure")
        }
        try inner.writeAtomically(data, to: name)
    }
}
