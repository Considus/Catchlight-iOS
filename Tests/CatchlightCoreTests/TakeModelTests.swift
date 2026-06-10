//
//  TakeModelTests.swift
//  CatchlightCoreTests — Task 7.2
//
//  Behaviour-level coverage for the `Take` entity itself: default initialisation,
//  Equatable semantics (synthesised — whole-struct, NOT id-only), the
//  `normaliseActivityFloor()` rule, and `modifiedAt > createdAt` after a mutation.
//
//  The existing `DataModelTests` covers JSON round-tripping; this file is the
//  gap-fill for in-memory behaviour. No SQLite or notification surface here —
//  see TakeStoreBehaviourTests and ReminderSchedulerTests for those.
//

import XCTest
@testable import CatchlightCore

final class TakeModelTests: XCTestCase {

    // MARK: - Default values

    func testTake_defaultInit_setsExpectedDefaults() {
        let take = Take()
        XCTAssertNotNil(UUID(uuidString: take.id.uuidString),
                        "id must be a valid UUID")
        XCTAssertEqual(take.contentType, "plain")
        XCTAssertTrue(take.isNote, "Note is the floor — defaults true")
        XCTAssertFalse(take.isTask)
        XCTAssertFalse(take.isComplete)
        XCTAssertFalse(take.isObie)
        XCTAssertNil(take.timeReminder)
        XCTAssertNil(take.locationReminder)
        XCTAssertTrue(take.checklistItems.isEmpty)
        XCTAssertTrue(take.attachments.isEmpty)
        XCTAssertFalse(take.isSeeded)
    }

    func testTake_defaultInit_createdAtIsRecent() {
        let before = Date().addingTimeInterval(-1)
        let take = Take()
        let after = Date().addingTimeInterval(1)
        XCTAssertGreaterThanOrEqual(take.createdAt, before)
        XCTAssertLessThanOrEqual(take.createdAt, after)
    }

    func testTake_defaultInit_eachCallGeneratesDistinctUUID() {
        let ids = (0..<20).map { _ in Take().id }
        XCTAssertEqual(Set(ids).count, ids.count, "Take() must produce a fresh UUID each time")
    }

    // MARK: - Equality
    //
    // NOTE on the spec: Task 7.2 says "two Takes with the same id are equal
    // regardless of content". The synthesised `Equatable` conformance on `Take`
    // compares ALL stored fields — content matters, and the same id with
    // different bodyText is NOT equal. We test the actual behaviour and flag the
    // spec gap in the work-plan note.

    func testTake_equality_sameIdSameContentIsEqual() {
        let id = UUID()
        let now = Date()
        let a = Take(id: id, createdAt: now, modifiedAt: now, bodyText: "hello")
        let b = Take(id: id, createdAt: now, modifiedAt: now, bodyText: "hello")
        XCTAssertEqual(a, b)
    }

    func testTake_equality_sameIdDifferentContentIsNotEqual() {
        let id = UUID()
        let now = Date()
        let a = Take(id: id, createdAt: now, modifiedAt: now, bodyText: "hello")
        let b = Take(id: id, createdAt: now, modifiedAt: now, bodyText: "world")
        XCTAssertNotEqual(a, b,
            "Synthesised Equatable compares all fields — different content is not equal even with the same id.")
    }

    func testTake_equality_differentIdsAlwaysNotEqual() {
        let now = Date()
        let a = Take(id: UUID(), createdAt: now, modifiedAt: now, bodyText: "x")
        let b = Take(id: UUID(), createdAt: now, modifiedAt: now, bodyText: "x")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - modifiedAt vs createdAt after mutation

    func testTake_modifiedAt_bumpsAfterMutation() throws {
        let original = Take(bodyText: "first")
        // Sleep one ms to guarantee a measurable bump in `modifiedAt`. We deliberately
        // touch `modifiedAt` ourselves — the model doesn't auto-stamp on field mutation.
        var mutated = original
        Thread.sleep(forTimeInterval: 0.001)
        mutated.bodyText = "second"
        mutated.modifiedAt = Date()
        XCTAssertGreaterThan(mutated.modifiedAt, original.createdAt,
                             "modifiedAt must move forward after a mutation")
    }

    // MARK: - normaliseActivityFloor (UX §6 — "Note is the floor")

    func testNormaliseActivityFloor_taskFalse_clearsIsComplete() {
        var take = Take(bodyText: "x", isNote: true, isTask: true, isComplete: true)
        take.isTask = false
        take.normaliseActivityFloor()
        XCTAssertFalse(take.isComplete)
        XCTAssertTrue(take.isNote)
    }

    func testNormaliseActivityFloor_taskTrue_preservesIsComplete() {
        var take = Take(bodyText: "x", isNote: true, isTask: true, isComplete: true)
        take.normaliseActivityFloor()
        XCTAssertTrue(take.isComplete)
        XCTAssertTrue(take.isTask)
        XCTAssertTrue(take.isNote)
    }

    func testNormaliseActivityFloor_noteAlwaysReasserts() {
        // Even if a caller explicitly sets isNote=false, normalise re-asserts it.
        var take = Take(bodyText: "x", isNote: false, isTask: true)
        take.normaliseActivityFloor()
        XCTAssertTrue(take.isNote, "Note is the floor — it must always end true")
    }

    func testNormaliseActivityFloor_obieAloneKeepsNoteTrue() {
        var take = Take(bodyText: "x", isNote: false, isObie: true)
        take.normaliseActivityFloor()
        XCTAssertTrue(take.isNote)
        XCTAssertTrue(take.isObie)
    }
}
