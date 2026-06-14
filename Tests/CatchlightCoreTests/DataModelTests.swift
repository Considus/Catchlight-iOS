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
        let take = Take(createdAt: nowMs, modifiedAt: nowMs, blocks: [])
        let data = try PlatformJSON.encode(take)
        let decoded = try PlatformJSON.decode(Take.self, from: data)
        XCTAssertEqual(decoded, take)
        XCTAssertTrue(decoded.blocks.isEmpty)
        XCTAssertTrue(decoded.checkItems.isEmpty)
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
        XCTAssertNil(Take(blocks: [.textLine("x")]).locationReminder)
        XCTAssertNil(TestFixtures.richTake().locationReminder)
    }

    // "Note is the floor" (UX §6): removing all activity types re-asserts Note,
    // and completion (derived) falls away once there are no check items.
    func testNoteFloor() {
        var take = Take(blocks: [.checkItem("x", isComplete: true)], isNote: true)
        XCTAssertTrue(take.isComplete)
        take.setTask(false)
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
        let filter = SequenceFilter(text: "shoot", requireTask: true, months: ["2026-06"])
        let seq = CatchlightSequence(
            name: "Weekend shoot",
            createdAt: nowMs,
            modifiedAt: nowMs,
            filter: filter
        )
        let decoded = try PlatformJSON.decode(CatchlightSequence.self, from: try PlatformJSON.encode(seq))
        XCTAssertEqual(decoded, seq)
        XCTAssertEqual(decoded.filter, filter)
        XCTAssertEqual(decoded.schemaVersion, CatchlightSequence.currentSchemaVersion)
    }

    /// A v1 Sequence payload (ordered takeIds list, no filter) decodes into the
    /// v2 model: the dead list is ignored and the filter defaults to empty.
    func testLegacySequencePayload_decodesWithEmptyFilter() throws {
        let legacy = """
        {"createdAt":"2026-05-28T07:00:00.000Z","id":"550E8400-E29B-41D4-A716-446655440000","modifiedAt":"2026-05-28T07:00:00.000Z","name":"Old list","takeIds":["550E8400-E29B-41D4-A716-446655440001"]}
        """
        let decoded = try PlatformJSON.decode(CatchlightSequence.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.name, "Old list")
        XCTAssertTrue(decoded.filter.isEmpty)
        XCTAssertEqual(decoded.schemaVersion, CatchlightSequence.currentSchemaVersion)
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

    // Take payloads carry the schemaVersion stamp; v2 (D-035) is the block model.
    func testTakeJSONIncludesSchemaVersion() throws {
        let take = TestFixtures.richTake()
        let json = String(data: try PlatformJSON.encode(take), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"schemaVersion\":2"), "encoded Take must carry the v2 stamp")
        XCTAssertEqual(take.schemaVersion, Take.currentSchemaVersion)
    }

    // A v1 payload (bodyText + checklistItems, no `blocks`) upgrades to the block
    // model on decode: one prose block for the body, then the items as check
    // blocks. The upgraded Take is re-stamped to the current version so a save
    // never persists v2 content under a v1 stamp.
    func testV1Payload_upgradesBodyTextAndItemsToBlocks() throws {
        let legacy = """
        {"id":"6B4D9E20-1A2B-4C3D-8E5F-001122334455",\
        "createdAt":"2026-05-01T09:00:00.000Z","modifiedAt":"2026-05-02T10:30:00.000Z",\
        "bodyText":"legacy note","contentType":"plain",\
        "isNote":true,"isTask":true,"isComplete":false,"isObie":false,\
        "checklistItems":[{"id":"6B4D9E20-1A2B-4C3D-8E5F-001122334456","text":"sub one","isComplete":true}]}
        """
        let decoded = try PlatformJSON.decode(Take.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.schemaVersion, Take.currentSchemaVersion, "upgrade re-stamps to current version")
        XCTAssertEqual(decoded.blocks.count, 2)
        XCTAssertEqual(decoded.blocks.first?.text, "legacy note")
        if case .text? = decoded.blocks.first {} else { XCTFail("first block must be prose") }
        XCTAssertEqual(decoded.checkItems.map(\.text), ["sub one"])
        XCTAssertTrue(decoded.checkItems.first?.isComplete ?? false)
        XCTAssertTrue(decoded.isTask, "a check block makes it a Task")
        XCTAssertEqual(decoded.attachments, [])
        XCTAssertFalse(decoded.isSeeded)
        XCTAssertNil(decoded.timeReminder)
    }

    // A v1 payload with bodyText only (no checklistItems) upgrades to a single
    // prose block and is therefore a plain Note, not a Task.
    func testV1Payload_bodyOnly_upgradesToSingleProseBlock() throws {
        let legacy = """
        {"id":"6B4D9E20-1A2B-4C3D-8E5F-00112233AABB",\
        "createdAt":"2026-05-01T09:00:00.000Z","modifiedAt":"2026-05-02T10:30:00.000Z",\
        "bodyText":"just a thought","contentType":"plain",\
        "isNote":true,"isTask":false,"isComplete":false,"isObie":false}
        """
        let decoded = try PlatformJSON.decode(Take.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.plainText, "just a thought")
        XCTAssertEqual(decoded.blocks.count, 1)
        XCTAssertFalse(decoded.isTask)
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
        let take = Take(createdAt: raw, modifiedAt: raw, blocks: [.textLine("ms")])
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
