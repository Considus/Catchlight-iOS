//
//  SQLiteTakeStoreTests.swift
//  CatchlightCoreTests — Task 7.2
//
//  Round-trip + invariant coverage for the production `SQLiteTakeStore`. The
//  in-memory store is exercised by `TakeStoreBehaviourTests`; this file is the
//  gap-fill for the SQLite serialisation path — date precision (ISO-8601 via
//  the wire format), optional JSON columns, UUID string round-trip, and the
//  Obie invariant under the SQLite implementation.
//
//  iOS-only: `SQLiteTakeStore` opens a database inside the App Group container,
//  so this suite is gated on `canImport(Catchlight)` and runs in the
//  `xcodebuild test` pass. The `swift test` macOS pass skips it cleanly.
//
//  ISOLATION: every test deletes the App Group `catchlight.db` file in
//  `setUp`/`tearDown` so runs are independent. This DOES touch the same path
//  the production app uses; tests must not be run against a simulator that
//  also has live user data. CI simulators start fresh, so it's safe there.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight
@testable import CatchlightCore
import CryptoKit

final class SQLiteTakeStoreTests: XCTestCase {

    private var store: SQLiteTakeStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try Self.removeDBFile()
        let keys = KeyHierarchy(masterKey: SymmetricKey(size: .bits256))
        store = try SQLiteTakeStore(keys: keys)
    }

    override func tearDownWithError() throws {
        store = nil
        try Self.removeDBFile()
        try super.tearDownWithError()
    }

    private static func removeDBFile() throws {
        let url = AppGroup.containerURL().appendingPathComponent("catchlight.db")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Field round-trips

    func testSQLite_upsertAndFetch_roundTripsAllFields() throws {
        let take = TestFixtures.richTake()
        try store.upsert(take)
        let read = try XCTUnwrap(try store.take(id: take.id))
        XCTAssertEqual(read, take, "All fields must round-trip through SQLite")
    }

    /// Dates are stored as ISO-8601 millisecond strings — re-reading must give
    /// back a `Date` that compares equal at ms precision. We construct the input
    /// from a canonical ms-aligned string so the comparison is bit-exact.
    func testSQLite_dateMillisecondPrecisionRoundTrip() throws {
        let isoString = "2026-05-28T07:00:00.123Z"
        let date = try XCTUnwrap(ISO8601.date(from: isoString))
        let take = Take(id: UUID(), createdAt: date, modifiedAt: date, bodyText: "ms-precision")
        try store.upsert(take)
        let read = try XCTUnwrap(try store.take(id: take.id))
        XCTAssertEqual(ISO8601.string(from: read.createdAt), isoString)
        XCTAssertEqual(ISO8601.string(from: read.modifiedAt), isoString)
    }

    func testSQLite_optionalFields_preservesNil() throws {
        let isoString = "2026-05-28T07:00:00.000Z"
        let date = try XCTUnwrap(ISO8601.date(from: isoString))
        let take = Take(
            id: UUID(),
            createdAt: date,
            modifiedAt: date,
            bodyText: "minimal",
            timeReminder: nil,
            locationReminder: nil
        )
        try store.upsert(take)
        let read = try XCTUnwrap(try store.take(id: take.id))
        XCTAssertNil(read.timeReminder)
        XCTAssertNil(read.locationReminder)
        XCTAssertEqual(read.checklistItems, [])
        XCTAssertEqual(read.attachments, [])
    }

    func testSQLite_uuidStringRoundTrip() throws {
        // Verify a specific UUID byte pattern survives the TEXT column round trip.
        let id = try XCTUnwrap(UUID(uuidString: "DEADBEEF-1234-5678-9ABC-DEF012345678"))
        let take = Take(id: id, bodyText: "uuid")
        try store.upsert(take)
        let read = try XCTUnwrap(try store.take(id: id))
        XCTAssertEqual(read.id, id)
    }

    // MARK: - CRUD invariants

    func testSQLite_deleteRemovesRecord() throws {
        let take = Take(bodyText: "doomed")
        try store.upsert(take)
        try store.delete(id: take.id)
        XCTAssertNil(try store.take(id: take.id))
    }

    func testSQLite_deleteUnknownId_throwsNotFound() {
        XCTAssertThrowsError(try store.delete(id: UUID())) { error in
            guard case StorageError.notFound = error else {
                return XCTFail("Expected .notFound, got \(error)")
            }
        }
    }

    func testSQLite_upsertSameIdReplaces() throws {
        let id = UUID()
        let date = Date()
        try store.upsert(Take(id: id, createdAt: date, modifiedAt: date, bodyText: "v1"))
        try store.upsert(Take(id: id, createdAt: date, modifiedAt: date, bodyText: "v2"))
        let all = try store.allTakes()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.bodyText, "v2")
    }

    func testSQLite_allTakesEmptyStore() throws {
        XCTAssertEqual(try store.allTakes(), [])
    }

    /// 500 Takes through the SQLite path — picks up any iteration-count / bind-
    /// param off-by-one in `upsert`.
    func testSQLite_largeBatch_500Takes() throws {
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

    // MARK: - Obie invariant under the SQLite implementation

    func testSQLite_obie_replaceExistingDemotesFirst() throws {
        let a = Take(bodyText: "a"); let b = Take(bodyText: "b")
        try store.upsert(a); try store.upsert(b)
        try store.setObie(id: a.id, replaceExisting: false)
        try store.setObie(id: b.id, replaceExisting: true)
        XCTAssertEqual(try store.currentObie()?.id, b.id)
        XCTAssertFalse(try XCTUnwrap(try store.take(id: a.id)).isObie)
        let count = try store.allTakes().filter(\.isObie).count
        XCTAssertEqual(count, 1)
    }

    func testSQLite_obie_conflictWithoutReplaceThrows() throws {
        let a = Take(bodyText: "a"); let b = Take(bodyText: "b")
        try store.upsert(a); try store.upsert(b)
        try store.setObie(id: a.id, replaceExisting: false)
        XCTAssertThrowsError(try store.setObie(id: b.id, replaceExisting: false)) { error in
            guard case StorageError.obieConflict = error else {
                return XCTFail("Expected .obieConflict, got \(error)")
            }
        }
    }
}
#endif
