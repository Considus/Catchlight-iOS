//
//  TakeModelTests.swift
//  CatchlightCoreTests — Task 7.2 / D-035
//
//  Behaviour-level coverage for the `Take` entity itself: default initialisation,
//  Equatable semantics (synthesised — whole-struct, NOT id-only), the
//  `normaliseActivityFloor()` rule, the derived `isTask`/`isComplete`/`plainText`,
//  and `modifiedAt > createdAt` after a mutation.
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
        XCTAssertEqual(take.contentType, "blocks/v2")
        XCTAssertTrue(take.isNote, "Note is the floor — defaults true")
        XCTAssertFalse(take.isTask)
        XCTAssertFalse(take.isComplete)
        XCTAssertFalse(take.isObie)
        XCTAssertNil(take.timeReminder)
        XCTAssertNil(take.locationReminder)
        XCTAssertTrue(take.blocks.isEmpty)
        XCTAssertTrue(take.checkItems.isEmpty)
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

    // MARK: - Derived properties (D-035)

    func testTake_isTask_trueWhenAnyCheckBlock() {
        let note = Take(blocks: [.textLine("just prose")])
        XCTAssertFalse(note.isTask)
        let task = Take(blocks: [.textLine("prose"), .checkItem("do this")])
        XCTAssertTrue(task.isTask, "a Take with ≥1 check block is a Task")
    }

    func testTake_isComplete_requiresChecksAndAllTicked() {
        XCTAssertFalse(Take(blocks: [.textLine("x")]).isComplete,
                       "a note with no checks is never complete")
        XCTAssertFalse(Take(blocks: [.checkItem("a"), .checkItem("b", isComplete: true)]).isComplete,
                       "one unticked item ⇒ incomplete")
        XCTAssertTrue(Take(blocks: [.checkItem("a", isComplete: true),
                                    .checkItem("b", isComplete: true)]).isComplete,
                      "all items ticked ⇒ complete")
        XCTAssertTrue(Take(blocks: [.textLine("header"), .checkItem("only", isComplete: true)]).isComplete,
                      "interleaved prose doesn't affect completion")
    }

    func testTake_plainText_joinsProseAndItemLabels() {
        let take = Take(blocks: [.textLine("Shopping"),
                                 .checkItem("milk"),
                                 .checkItem("eggs", isComplete: true)])
        XCTAssertEqual(take.plainText, "Shopping\nmilk\neggs")
    }

    func testTake_checkItems_inBlockOrder() {
        let take = Take(blocks: [.checkItem("a"), .textLine("mid"), .checkItem("b", isComplete: true)])
        XCTAssertEqual(take.checkItems.map(\.text), ["a", "b"])
        XCTAssertEqual(take.checkItems.map(\.isComplete), [false, true])
    }

    // MARK: - Content mutation helpers (Phase-1 bridges)

    func testSetTask_promotesProseToCheckItems() {
        var take = Take(blocks: [.textLine("buy milk")])
        take.setTask(true)
        XCTAssertTrue(take.isTask)
        XCTAssertEqual(take.checkItems.map(\.text), ["buy milk"], "prose text carries into the item")
    }

    func testSetTask_onEmptyTakeAddsOneItem() {
        var take = Take()
        take.setTask(true)
        XCTAssertTrue(take.isTask)
        XCTAssertEqual(take.checkItems.count, 1)
    }

    func testSetTask_falseDemotesChecksToProse() {
        var take = Take(blocks: [.checkItem("buy milk", isComplete: true)])
        take.setTask(false)
        XCTAssertFalse(take.isTask)
        XCTAssertEqual(take.plainText, "buy milk", "item text is preserved as prose")
    }

    func testSetAllItemsComplete_ticksEveryItem() {
        var take = Take(blocks: [.checkItem("a"), .textLine("x"), .checkItem("b")])
        take.setAllItemsComplete(true)
        XCTAssertTrue(take.isComplete)
        take.setAllItemsComplete(false)
        XCTAssertFalse(take.isComplete)
    }

    func testPrimaryText_editsFirstProseBlockPreservingChecks() {
        var take = Take(blocks: [.textLine("draft"), .checkItem("item")])
        take.primaryText = "revised"
        XCTAssertEqual(take.primaryText, "revised")
        XCTAssertTrue(take.isTask, "editing prose must not drop the check block")
        XCTAssertEqual(take.checkItems.map(\.text), ["item"])
    }

    func testPrimaryText_insertsProseBlockWhenNone() {
        var take = Take(blocks: [.checkItem("item")])
        XCTAssertEqual(take.primaryText, "")
        take.primaryText = "context"
        XCTAssertEqual(take.primaryText, "context")
        XCTAssertTrue(take.isTask)
    }

    // MARK: - Equality (synthesised — whole-struct, NOT id-only)

    func testTake_equality_sameIdSameContentIsEqual() {
        let id = UUID()
        let now = Date()
        let block = TakeBlock.textLine("hello")
        let a = Take(id: id, createdAt: now, modifiedAt: now, blocks: [block])
        let b = Take(id: id, createdAt: now, modifiedAt: now, blocks: [block])
        XCTAssertEqual(a, b)
    }

    func testTake_equality_sameIdDifferentContentIsNotEqual() {
        let id = UUID()
        let now = Date()
        let a = Take(id: id, createdAt: now, modifiedAt: now, blocks: [.textLine("hello")])
        let b = Take(id: id, createdAt: now, modifiedAt: now, blocks: [.textLine("world")])
        XCTAssertNotEqual(a, b,
            "Synthesised Equatable compares all fields — different content is not equal even with the same id.")
    }

    func testTake_equality_differentIdsAlwaysNotEqual() {
        let now = Date()
        let a = Take(id: UUID(), createdAt: now, modifiedAt: now, blocks: [.textLine("x")])
        let b = Take(id: UUID(), createdAt: now, modifiedAt: now, blocks: [.textLine("x")])
        XCTAssertNotEqual(a, b)
    }

    // MARK: - modifiedAt vs createdAt after mutation

    func testTake_modifiedAt_bumpsAfterMutation() throws {
        let original = Take(blocks: [.textLine("first")])
        // Sleep one ms to guarantee a measurable bump in `modifiedAt`. We deliberately
        // touch `modifiedAt` ourselves — the model doesn't auto-stamp on field mutation.
        var mutated = original
        Thread.sleep(forTimeInterval: 0.001)
        mutated.primaryText = "second"
        mutated.modifiedAt = Date()
        XCTAssertGreaterThan(mutated.modifiedAt, original.createdAt,
                             "modifiedAt must move forward after a mutation")
    }

    // MARK: - normaliseActivityFloor (UX §6 — "Note is the floor")

    func testNormaliseActivityFloor_demotedTaskIsNoLongerComplete() {
        // A complete Task, demoted to prose, has no check items so completion
        // (derived) falls away on its own; the floor keeps Note true.
        var take = Take(blocks: [.checkItem("x", isComplete: true)])
        XCTAssertTrue(take.isComplete)
        take.setTask(false)
        take.normaliseActivityFloor()
        XCTAssertFalse(take.isComplete)
        XCTAssertTrue(take.isNote)
    }

    func testNormaliseActivityFloor_taskStaysCompleteWhenItemsTicked() {
        var take = Take(blocks: [.checkItem("x", isComplete: true)])
        take.normaliseActivityFloor()
        XCTAssertTrue(take.isComplete)
        XCTAssertTrue(take.isTask)
        XCTAssertTrue(take.isNote)
    }

    func testNormaliseActivityFloor_noteAlwaysReasserts() {
        // Even if a caller explicitly sets isNote=false, normalise re-asserts it.
        var take = Take(blocks: [.checkItem("x")], isNote: false)
        take.normaliseActivityFloor()
        XCTAssertTrue(take.isNote, "Note is the floor — it must always end true")
    }

    func testNormaliseActivityFloor_obieAloneKeepsNoteTrue() {
        var take = Take(blocks: [.textLine("x")], isNote: false, isObie: true)
        take.normaliseActivityFloor()
        XCTAssertTrue(take.isNote)
        XCTAssertTrue(take.isObie)
    }
}
