//
//  DataModelTests.swift
//  CatchlightCoreTests
//
//  Phase 5 brief §12.2 — data model.
//

import XCTest
@testable import CatchlightCore

final class DataModelTests: XCTestCase {

    // §12.2 — Take round-trips through JSON serialisation with all fields preserved.
    func testTakeRoundTripAllFields() throws {
        let take = TestFixtures.richTake()
        let data = try PlatformJSON.encode(take)
        let decoded = try PlatformJSON.decode(Take.self, from: data)
        XCTAssertEqual(decoded, take)
    }

    // §12.2 — Take with all fields at nil/empty still serialises and deserialises.
    func testEmptyTakeRoundTrip() throws {
        // Millisecond-aligned date: the canonical wire format is ms-precision, so a
        // raw Date() would not be bit-exact after a round-trip (documented).
        let nowMs = ISO8601.date(from: ISO8601.string(from: Date()))!
        let take = Take(createdAt: nowMs, modifiedAt: nowMs, bodyText: "")
        let data = try PlatformJSON.encode(take)
        let decoded = try PlatformJSON.decode(Take.self, from: data)
        XCTAssertEqual(decoded, take)
        XCTAssertTrue(decoded.checklistItems.isEmpty)
        XCTAssertTrue(decoded.attachments.isEmpty)
        XCTAssertNil(decoded.timeReminder)
        XCTAssertNil(decoded.locationReminder)
        XCTAssertTrue(decoded.isNote)
    }

    // §12.2 — ISO 8601 date encoding used throughout — no Apple-specific formats.
    func testISO8601DateEncoding() throws {
        let take = TestFixtures.richTake()
        let data = try PlatformJSON.encode(take)
        let json = String(data: data, encoding: .utf8)!
        // The created/modified dates appear as explicit ISO-8601 Z strings.
        XCTAssertTrue(json.contains("2026-05-01T09:00:00.000Z"), "createdAt must be ISO-8601 UTC")
        XCTAssertTrue(json.contains("2026-05-02T10:30:00.000Z"), "modifiedAt must be ISO-8601 UTC")
        // No Apple reference-date Double leaked in (e.g. 7..e8 seconds-since-2001).
        XCTAssertFalse(json.contains("\"createdAt\":7"), "must not be a JSONEncoder default Double date")
    }

    func testCanonicalDateFormat() {
        let date = ISO8601.date(from: "2026-05-28T07:00:00.000Z")!
        XCTAssertEqual(ISO8601.string(from: date), "2026-05-28T07:00:00.000Z")
        // Tolerant parse of the seconds-only literal used in spec examples.
        XCTAssertNotNil(ISO8601.date(from: "2026-05-28T07:00:00Z"))
    }

    // §12.2 — ChecklistItem has only id, text, isComplete — no other fields.
    func testChecklistItemShape() throws {
        let item = ChecklistItem(text: "thing", isComplete: true)
        let json = String(data: try PlatformJSON.encode(item), encoding: .utf8)!
        let keys = Set(json
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .split(separator: ",")
            .map { $0.split(separator: ":")[0].trimmingCharacters(in: CharacterSet(charactersIn: " \"")) })
        XCTAssertEqual(keys, ["id", "text", "isComplete"])
        XCTAssertFalse(json.contains("reminder"))
        XCTAssertFalse(json.contains("linkedTakeId"))
        XCTAssertFalse(json.contains("linkedTake"))
    }

    // §12.2 — locationReminder is always nil in v1.0.
    func testLocationReminderNilInV1() {
        // Default and fixture Takes never populate locationReminder.
        XCTAssertNil(Take(bodyText: "x").locationReminder)
        XCTAssertNil(TestFixtures.richTake().locationReminder)
    }

    // "Note is the floor" (UX §6): removing all activity types re-asserts Note.
    func testNoteFloor() {
        var take = Take(bodyText: "x", isNote: true, isTask: true, isComplete: true)
        take.isTask = false
        take.normaliseActivityFloor()
        XCTAssertTrue(take.isNote)
        XCTAssertFalse(take.isComplete, "completion clears when not a task")
    }

    // CatchlightSequence (the Swift type avoiding the reserved `Sequence` name).
    func testSequenceRoundTrip() throws {
        // Millisecond-aligned dates: the canonical wire format is ms-precision
        // (ISO8601.swift uses `.SSS` deliberately for cross-platform conflict
        // detection), so a raw Date() is not bit-exact after a round-trip — see
        // testEmptyTakeRoundTrip above, which documents the same constraint.
        let nowMs = ISO8601.date(from: ISO8601.string(from: Date()))!
        let seq = CatchlightSequence(
            name: "Weekend shoot",
            createdAt: nowMs,
            modifiedAt: nowMs,
            takeIds: [UUID(), UUID()]
        )
        let decoded = try PlatformJSON.decode(CatchlightSequence.self, from: try PlatformJSON.encode(seq))
        XCTAssertEqual(decoded, seq)
        XCTAssertEqual(decoded.takeIds.count, 2)
    }

    // Account metadata is the only plaintext cloud file; round-trips with ISO-8601.
    func testAccountMetadataRoundTrip() throws {
        let meta = AccountMetadata(
            schemaVersion: 1,
            accountCreatedAt: "2026-05-28T07:00:00.000Z",
            argon2Salt: Data(repeating: 9, count: 16).base64EncodedString(),
            appVersion: "1.0.0"
        )
        let decoded = try PlatformJSON.decode(AccountMetadata.self, from: try PlatformJSON.encode(meta))
        XCTAssertEqual(decoded, meta)
    }

    // Deterministic key ordering (needed for reproducible HMAC + cross-platform).
    func testDeterministicKeyOrdering() throws {
        let take = TestFixtures.richTake()
        let a = try PlatformJSON.encode(take)
        let b = try PlatformJSON.encode(take)
        XCTAssertEqual(a, b)
    }
}
