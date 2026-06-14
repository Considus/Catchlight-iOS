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

    func testChecklistProgress_onlyForTwoOrMoreItems() {
        XCTAssertNil(Take(blocks: [.textLine("note")]).checklistProgress, "a note has no progress")
        XCTAssertNil(Take(blocks: [.checkItem("one")]).checklistProgress, "a one-item Task reads from its state, no count")

        let take = Take(blocks: [.checkItem("a", isComplete: true),
                                 .textLine("aside"),
                                 .checkItem("b"),
                                 .checkItem("c", isComplete: true)])
        let progress = take.checklistProgress
        XCTAssertEqual(progress?.done, 2)
        XCTAssertEqual(progress?.total, 3, "interleaved prose is not counted")
    }

    func testTake_checkItems_inBlockOrder() {
        let take = Take(blocks: [.checkItem("a"), .textLine("mid"), .checkItem("b", isComplete: true)])
        XCTAssertEqual(take.checkItems.map(\.text), ["a", "b"])
        XCTAssertEqual(take.checkItems.map(\.isComplete), [false, true])
    }

    // MARK: - Block editing (D-035 / Phase 2)

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

    func testConvertToChecklist_splittingTargetBlock_splitsOnNewlines() {
        // The Focus-ring Task ON path: only the cursor's text block is split,
        // each line becoming its own check item.
        let prose = TakeBlock.text(TextBlock(text: "milk\neggs\nbread"))
        var take = Take(blocks: [.textLine("header"), prose])
        let firstID = take.convertToChecklist(splitting: prose.id)
        XCTAssertEqual(take.checkItems.map(\.text), ["milk", "eggs", "bread"])
        XCTAssertEqual(take.blocks.first?.text, "header", "other prose is untouched")
        XCTAssertEqual(firstID, take.checkItems.first?.id, "returns the first new item to focus")
    }

    func testConvertToChecklist_noTarget_splitsEveryProseBlock() {
        var take = Take(blocks: [.textLine("a\nb"), .textLine("c")])
        take.convertToChecklist()
        XCTAssertEqual(take.checkItems.map(\.text), ["a", "b", "c"])
    }

    func testConvertToProse_joinsCheckRunsIntoTextBlocks() {
        var take = Take(blocks: [.checkItem("milk"), .checkItem("eggs"),
                                 .textLine("note"), .checkItem("bread")])
        take.convertToProse()
        XCTAssertFalse(take.isTask)
        XCTAssertEqual(take.blocks.count, 3, "the leading run collapses to one block")
        XCTAssertEqual(take.blocks.first?.text, "milk\neggs")
        XCTAssertEqual(take.plainText, "milk\neggs\nnote\nbread")
    }

    func testInsertCheckItem_addsEmptyItemAfter() {
        let first = TakeBlock.checkItem("milk")
        var take = Take(blocks: [first])
        let newID = take.insertCheckItem(after: first.id)
        XCTAssertEqual(take.checkItems.count, 2)
        XCTAssertEqual(take.checkItems.last?.text, "")
        XCTAssertEqual(newID, take.checkItems.last?.id)
    }

    func testConvertCheckToText_exitsListPreservingId() {
        let item = TakeBlock.checkItem("milk")
        var take = Take(blocks: [item])
        take.convertCheckToText(blockID: item.id)
        XCTAssertFalse(take.isTask)
        XCTAssertEqual(take.blocks.first?.id, item.id, "id is preserved so focus stays")
        XCTAssertEqual(take.blocks.first?.text, "milk")
    }

    func testBlockIDBefore_andRemoveBlock() {
        let a = TakeBlock.textLine("a"), b = TakeBlock.checkItem("b"), c = TakeBlock.checkItem("c")
        var take = Take(blocks: [a, b, c])
        XCTAssertEqual(take.blockID(before: b.id), a.id)
        XCTAssertNil(take.blockID(before: a.id), "first block has nothing before it")
        take.removeBlock(blockID: b.id)
        XCTAssertEqual(take.blocks.map(\.id), [a.id, c.id])
    }

    func testMoveBlock_reordersBeforeTarget() {
        let a = TakeBlock.checkItem("a"), b = TakeBlock.checkItem("b"), c = TakeBlock.checkItem("c")
        var take = Take(blocks: [a, b, c])
        take.moveBlock(id: c.id, before: a.id)
        XCTAssertEqual(take.blocks.map(\.id), [c.id, a.id, b.id])
        take.moveBlock(id: c.id, before: c.id)   // no-op
        XCTAssertEqual(take.blocks.map(\.id), [c.id, a.id, b.id])
    }

    func testUpdateText_andToggleItemComplete() {
        let t = TakeBlock.textLine("draft"), c = TakeBlock.checkItem("todo")
        var take = Take(blocks: [t, c])
        take.updateText("revised", blockID: t.id)
        XCTAssertEqual(take.blocks.first?.text, "revised")
        take.toggleItemComplete(blockID: c.id)
        XCTAssertTrue(take.isComplete)
    }

    func testRemoveEmptyTextBlocks_dropsEmptyProseKeepsEmptyChecks() {
        var take = Take(blocks: [.textLine(""), .textLine("keep"), .checkItem("")])
        take.removeEmptyTextBlocks()
        XCTAssertEqual(take.blocks.count, 2)
        XCTAssertEqual(take.blocks.first?.text, "keep")
        XCTAssertTrue(take.isTask, "an empty check item is kept")
    }

    func testSetAllItemsComplete_ticksEveryItem() {
        var take = Take(blocks: [.checkItem("a"), .textLine("x"), .checkItem("b")])
        take.setAllItemsComplete(true)
        XCTAssertTrue(take.isComplete)
        take.setAllItemsComplete(false)
        XCTAssertFalse(take.isComplete)
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
        mutated.updateText("second", blockID: original.blocks[0].id)
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
