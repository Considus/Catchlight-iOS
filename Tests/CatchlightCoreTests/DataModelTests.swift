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
    // `argon2Salt` was REMOVED 2026-06-10 (HKDF uses a fixed domain salt).
    func testAccountMetadataRoundTrip() throws {
        let meta = AccountMetadata(
            schemaVersion: 1,
            accountCreatedAt: "2026-05-28T07:00:00.000Z",
            appVersion: "1.0.0"
        )
        let decoded = try PlatformJSON.decode(AccountMetadata.self, from: try PlatformJSON.encode(meta))
        XCTAssertEqual(decoded, meta)
    }

    // A metadata file written by an earlier dev build (with the removed
    // `argon2Salt` field) still decodes — the field is simply ignored.
    func testAccountMetadataDecodingIgnoresLegacyArgon2SaltField() throws {
        let json = """
        {"accountCreatedAt":"2026-05-28T07:00:00.000Z","appVersion":"0.9.0",\
        "argon2Salt":"CQkJCQkJCQkJCQkJCQkJCQ==","schemaVersion":1}
        """
        let decoded = try PlatformJSON.decode(AccountMetadata.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.appVersion, "0.9.0")
    }

    // Take payloads carry the schemaVersion stamp (2026-06-10) and decode old
    // payloads without one as version 1.
    func testTakeJSONIncludesSchemaVersion_andDefaultsWhenAbsent() throws {
        let take = TestFixtures.richTake()
        let json = String(data: try PlatformJSON.encode(take), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"schemaVersion\":1"), "encoded Take must carry the version stamp")

        // A pre-2026-06-10 payload (no schemaVersion key) decodes as v1, with
        // decodeIfPresent defaults for the optional/array fields.
        let legacy = """
        {"id":"6B4D9E20-1A2B-4C3D-8E5F-001122334455",\
        "createdAt":"2026-05-01T09:00:00.000Z","modifiedAt":"2026-05-02T10:30:00.000Z",\
        "bodyText":"legacy","contentType":"plain",\
        "isNote":true,"isTask":false,"isComplete":false,"isObie":false}
        """
        let decoded = try PlatformJSON.decode(Take.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.bodyText, "legacy")
        XCTAssertEqual(decoded.checklistItems, [])
        XCTAssertEqual(decoded.attachments, [])
        XCTAssertEqual(decoded.sequenceIds, [])
        XCTAssertFalse(decoded.isSeeded)
        XCTAssertNil(decoded.timeReminder)
    }

    // ISO8601.date(from:) tolerant INPUT parsing (2026-06-10): 0–9 fractional
    // digits and ±HH:MM offsets all parse; canonical OUTPUT stays `.SSS'Z'`.
    func testISO8601TolerantParsing_fractionalDigitsAndOffsets() {
        let expected = ISO8601.date(from: "2026-05-28T07:00:00.123Z")!

        XCTAssertEqual(ISO8601.date(from: "2026-05-28T07:00:00.123456Z"), expected,
                       "6 fractional digits truncate to milliseconds")
        XCTAssertEqual(ISO8601.date(from: "2026-05-28T07:00:00.123456789Z"), expected,
                       "9 fractional digits truncate to milliseconds")
        XCTAssertEqual(ISO8601.date(from: "2026-05-28T07:00:00.1Z"),
                       ISO8601.date(from: "2026-05-28T07:00:00.100Z"),
                       "'.1' means 100 ms, not 1 ms")

        // Zero fractional digits.
        let secondsOnly = ISO8601.date(from: "2026-05-28T07:00:00Z")
        XCTAssertEqual(secondsOnly, ISO8601.date(from: "2026-05-28T07:00:00.000Z"))

        // ±HH:MM (and ±HHMM) offsets.
        XCTAssertEqual(ISO8601.date(from: "2026-05-28T07:00:00+00:00"), secondsOnly)
        XCTAssertEqual(ISO8601.date(from: "2026-05-28T09:00:00+02:00"), secondsOnly)
        XCTAssertEqual(ISO8601.date(from: "2026-05-28T02:00:00-05:00"), secondsOnly)
        XCTAssertEqual(ISO8601.date(from: "2026-05-28T09:00:00+0200"), secondsOnly)
        XCTAssertEqual(ISO8601.date(from: "2026-05-28T08:30:00.123456+01:30"), expected)

        // Garbage still rejected.
        XCTAssertNil(ISO8601.date(from: "not-a-date"))
        XCTAssertNil(ISO8601.date(from: "2026-05-28T07:00:00"))
        XCTAssertNil(ISO8601.date(from: "2026-05-28"))
    }

    // truncateToMilliseconds: a Take's timestamps are ms-aligned at init, so it
    // compares equal to itself after a wire round-trip even from a raw Date().
    func testTakeTimestampsTruncatedToMilliseconds() throws {
        let raw = Date(timeIntervalSince1970: 1_700_000_000.123_456_789)
        let take = Take(createdAt: raw, modifiedAt: raw, bodyText: "ms")
        let decoded = try PlatformJSON.decode(Take.self, from: try PlatformJSON.encode(take))
        XCTAssertEqual(decoded, take, "ms-truncation at init makes round-trips bit-exact")
        XCTAssertEqual(take.createdAt, ISO8601.truncateToMilliseconds(raw))
    }

    // Deterministic key ordering (needed for reproducible HMAC + cross-platform).
    func testDeterministicKeyOrdering() throws {
        let take = TestFixtures.richTake()
        let a = try PlatformJSON.encode(take)
        let b = try PlatformJSON.encode(take)
        XCTAssertEqual(a, b)
    }
}
