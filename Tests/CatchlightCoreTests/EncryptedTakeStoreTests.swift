//
//  EncryptedTakeStoreTests.swift
//  CatchlightCoreTests — 2026-06-10 remediation (formerly SQLiteTakeStoreTests)
//
//  Coverage for the production `EncryptedTakeStore` (SQLite3, per-item
//  AES-256-GCM sealed payload columns — schema v2). Two suites:
//
//    • `EncryptedTakeStoreContractTests` — runs the ENTIRE shared TakeStore
//      contract (TakeStoreContractTests.swift) against the production store, so
//      takesModified/search/lastSync/tombstones are proven identical to the
//      in-memory reference implementation.
//    • `EncryptedTakeStoreTests` — SQLite-specific gap-fill: serialisation
//      precision, persistence across close/reopen, and the encryption-at-rest
//      assertion (the DB file must never contain plaintext body text).
//
//  ISOLATION: every test opens the store on a FRESH temp directory (via
//  `init(keys:directoryURL:)`, added 2026-06-10 exactly for this) and removes
//  it in tearDown. The App Group container is NEVER touched — the previous
//  suite deleted the production `catchlight.db` path, which could destroy live
//  user data if run against a non-fresh simulator.
//
//  iOS-only: gated on `canImport(Catchlight)`; the `swift test` macOS pass
//  skips both suites cleanly.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight
@testable import CatchlightCore
import CryptoKit

// MARK: - Shared contract against the production store

final class EncryptedTakeStoreContractTests: TakeStoreContractTests {

    private var tempDir: URL!

    override func makeStore() throws -> TakeStore {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("catchlight-store-contract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let keys = KeyHierarchy(masterKey: SymmetricKey(size: .bits256))
        return try EncryptedTakeStore(keys: keys, directoryURL: tempDir)
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        tempDir = nil
    }
}

// MARK: - SQLite-specific coverage

final class EncryptedTakeStoreTests: XCTestCase {

    private var tempDir: URL!
    private var keys: KeyHierarchy!
    private var store: EncryptedTakeStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("catchlight-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        keys = KeyHierarchy(masterKey: SymmetricKey(size: .bits256))
        store = try EncryptedTakeStore(keys: keys, directoryURL: tempDir)
    }

    override func tearDownWithError() throws {
        store = nil
        keys = nil
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        tempDir = nil
        try super.tearDownWithError()
    }

    private var dbURL: URL {
        tempDir.appendingPathComponent("Database", isDirectory: true)
            .appendingPathComponent("catchlight.db")
    }

    /// Re-open a fresh store instance over the same directory (close/reopen).
    private func reopenStore() throws -> EncryptedTakeStore {
        store = nil   // deinit closes the SQLite handle
        return try EncryptedTakeStore(keys: keys, directoryURL: tempDir)
    }

    // MARK: - Serialisation precision

    /// Dates are stored as ISO-8601 millisecond strings — re-reading must give
    /// back a `Date` that compares equal at ms precision.
    func testEncryptedStore_dateMillisecondPrecisionRoundTrip() throws {
        let isoString = "2026-05-28T07:00:00.123Z"
        let date = try XCTUnwrap(ISO8601.date(from: isoString))
        let take = Take(id: UUID(), createdAt: date, modifiedAt: date, bodyText: "ms-precision")
        try store.upsert(take)
        let read = try XCTUnwrap(try store.take(id: take.id))
        XCTAssertEqual(ISO8601.string(from: read.createdAt), isoString)
        XCTAssertEqual(ISO8601.string(from: read.modifiedAt), isoString)
    }

    func testEncryptedStore_optionalFields_preserveNil() throws {
        let date = try XCTUnwrap(ISO8601.date(from: "2026-05-28T07:00:00.000Z"))
        let take = Take(id: UUID(), createdAt: date, modifiedAt: date, bodyText: "minimal",
                        timeReminder: nil, locationReminder: nil)
        try store.upsert(take)
        let read = try XCTUnwrap(try store.take(id: take.id))
        XCTAssertNil(read.timeReminder)
        XCTAssertNil(read.locationReminder)
        XCTAssertEqual(read.checklistItems, [])
        XCTAssertEqual(read.attachments, [])
    }

    func testEncryptedStore_uuidStringRoundTrip() throws {
        let id = try XCTUnwrap(UUID(uuidString: "DEADBEEF-1234-5678-9ABC-DEF012345678"))
        try store.upsert(Take(id: id, bodyText: "uuid"))
        XCTAssertEqual(try XCTUnwrap(try store.take(id: id)).id, id)
    }

    /// 500 Takes through the SQLite path — picks up any iteration-count /
    /// bind-param off-by-one in `upsert` and ordering at scale.
    func testEncryptedStore_largeBatch_500Takes() throws {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        for i in 0..<500 {
            try store.upsert(Take(
                id: UUID(),
                createdAt: base.addingTimeInterval(Double(i)),
                modifiedAt: base.addingTimeInterval(Double(i)),
                bodyText: "take-\(i)"
            ))
        }
        let all = try store.allTakes()
        XCTAssertEqual(all.count, 500)
        XCTAssertEqual(all.first?.bodyText, "take-0")
        XCTAssertEqual(all.last?.bodyText, "take-499")
    }

    // MARK: - Persistence across close/reopen (schema v2: sync_state, tombstones)

    /// `lastSyncDate` is PERSISTED (previously an in-memory var — every relaunch
    /// reset the sync watermark). It must survive a close + reopen.
    func testEncryptedStore_lastSyncDate_survivesReopen() throws {
        let stamp = try XCTUnwrap(ISO8601.date(from: "2026-06-01T12:00:00.500Z"))
        store.setLastSyncDate(stamp)

        let reopened = try reopenStore()
        XCTAssertEqual(reopened.lastSyncDate(), stamp,
                       "the sync watermark must survive a store close/reopen")
    }

    /// Tombstones are persisted too — a deletion recorded before a relaunch is
    /// still pending propagation after it.
    func testEncryptedStore_tombstones_surviveReopen() throws {
        let take = TestFixtures.richTake()
        try store.upsert(take)
        try store.delete(id: take.id)

        let reopened = try reopenStore()
        XCTAssertEqual(try reopened.tombstones().map(\.id), [take.id])
    }

    func testEncryptedStore_takes_surviveReopen() throws {
        let take = TestFixtures.richTake()
        try store.upsert(take)

        let reopened = try reopenStore()
        XCTAssertEqual(try reopened.take(id: take.id), take)
    }

    // MARK: - Encryption at rest

    /// The database file's raw bytes must NOT contain a known plaintext body
    /// string — body text is sealed with per-item AES-256-GCM before it touches
    /// disk. (The -wal sidecar is checked too: with WAL journaling recent writes
    /// may live there before a checkpoint.)
    func testEncryptedStore_dbFileBytes_doNotContainPlaintextBody() throws {
        let sentinel = "TOP-SECRET-PLAINTEXT-SENTINEL-c0ffee"
        var take = TestFixtures.richTake()
        take.bodyText = sentinel
        try store.upsert(take)

        // Close the store so the SQLite handle releases and WAL state settles.
        store = nil

        let needle = Data(sentinel.utf8)
        var checkedAnyFile = false
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: dbURL.path + suffix)
            guard let bytes = try? Data(contentsOf: url) else { continue }
            checkedAnyFile = true
            XCTAssertNil(bytes.range(of: needle),
                         "plaintext body found in \(url.lastPathComponent) — encryption at rest is broken")
        }
        XCTAssertTrue(checkedAnyFile, "expected at least the main DB file at \(dbURL.path)")
    }
}
#endif
