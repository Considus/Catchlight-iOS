//
//  DailiesViewModelMutationTests.swift
//  CatchlightCoreTests
//
//  The swipe actions (delete / mark-done) update the `takes` array IN PLACE rather than
//  re-fetching + re-sorting the whole timeline via `reload()` — the source of the swipe
//  "jank" (owner 2026-06-27). These tests pin the end state of the in-place paths: a delete
//  removes just that row and preserves order; a mark-done updates the row in place without
//  changing its position. App-target only (`DailiesViewModel` lives there).
//

#if canImport(Catchlight)
import XCTest
import UserNotifications
@testable import Catchlight
@testable import CatchlightCore

/// No-op notification centre so VM mutations never touch the live `UNUserNotificationCenter`.
private final class QuietCenter: NotificationScheduling {
    func add(_ request: UNNotificationRequest) {}
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
}

@MainActor
final class DailiesViewModelMutationTests: XCTestCase {

    private func makeVM(_ takes: [Take]) throws -> DailiesViewModel {
        let store = InMemoryTakeStore()
        for t in takes { try store.upsert(t) }
        return DailiesViewModel(store: store, reminders: ReminderScheduler(center: QuietCenter()))
    }

    /// Delete removes just that Take from `takes` (in place) and preserves the rest's order.
    func testDelete_removesInPlace_preservingOrder() throws {
        let a = Take(createdAt: Date(timeIntervalSince1970: 3), blocks: [.textLine("A")])
        let b = Take(createdAt: Date(timeIntervalSince1970: 2), blocks: [.textLine("B")])
        let c = Take(createdAt: Date(timeIntervalSince1970: 1), blocks: [.textLine("C")])
        let vm = try makeVM([a, b, c])
        XCTAssertEqual(vm.takes.map(\.id), [a.id, b.id, c.id])   // newest-first

        vm.delete(b)

        XCTAssertEqual(vm.takes.map(\.id), [a.id, c.id], "only B is removed; order preserved")
        XCTAssertNil(vm.lastError)
    }

    /// Deleting the Obie clears it in place (it lives in a pinned layer, not `takes`).
    func testDelete_obie_clearsInPlace() throws {
        let obie = Take(blocks: [.textLine("the one")], isObie: true)
        let other = Take(blocks: [.textLine("other")])
        let vm = try makeVM([obie, other])
        XCTAssertEqual(vm.obie?.id, obie.id)

        vm.delete(obie)

        XCTAssertNil(vm.obie, "the Obie is cleared")
        XCTAssertEqual(vm.takes.map(\.id), [other.id])
    }

    /// Long-press on an Obie's Iris demotes it back to a standard Take: the pinned
    /// Obie clears and the Take rejoins the timeline with `isObie == false`.
    func testDemoteObie_turnsBackIntoStandardTake() throws {
        let obie = Take(blocks: [.textLine("the one")], isObie: true)
        let other = Take(blocks: [.textLine("other")])
        let vm = try makeVM([obie, other])
        XCTAssertEqual(vm.obie?.id, obie.id)

        vm.demoteObie(obie)

        XCTAssertNil(vm.obie, "no Obie after demote")
        let demoted = try XCTUnwrap(vm.takes.first { $0.id == obie.id })
        XCTAssertFalse(demoted.isObie, "the Take is now a standard Take")
        XCTAssertNil(vm.lastError)
    }

    /// Mark-done updates the Take in place (keeps its position) rather than reloading.
    func testToggleDone_updatesInPlace_keepsPosition() throws {
        let task = Take(createdAt: Date(timeIntervalSince1970: 2), blocks: [.checkItem("do it")])
        let other = Take(createdAt: Date(timeIntervalSince1970: 1), blocks: [.textLine("note")])
        let vm = try makeVM([task, other])

        vm.toggleDone(task)

        let updated = try XCTUnwrap(vm.takes.first { $0.id == task.id })
        XCTAssertTrue(updated.isMarkedDone, "the Take is now done")
        XCTAssertEqual(vm.takes.map(\.id), [task.id, other.id], "position preserved, no re-sort")
    }

    // MARK: - "All tasks done. Stop reminding?" (owner 2026-08-11)

    private func reminderTake(prose: String?, items: [(String, Bool)],
                              recurrence: TimeReminder.Recurrence = .none) -> Take {
        let id = UUID()
        var blocks: [TakeBlock] = []
        if let prose { blocks.append(.textLine(prose)) }
        blocks += items.map { .checkItem($0.0, isComplete: $0.1) }
        return Take(id: id, blocks: blocks,
                    timeReminder: TimeReminder(scheduledDate: Date().addingTimeInterval(3600),
                                               notificationIdentifier: id.uuidString,
                                               recurrence: recurrence))
    }

    func testPrompt_raisedWhenLastItemTicked_onATakeWithANote() throws {
        let take = reminderTake(prose: "Ring the surveyor back",
                                items: [("find the report", true), ("scan it", false)])
        let vm = try makeVM([take])
        XCTAssertNil(vm.tasksCompletedTakeID)

        var done = take
        done.setAllItemsComplete(true)
        vm.noteTasksCompleted(done)
        XCTAssertEqual(vm.tasksCompletedTakeID, take.id)
    }

    /// Saving is no longer a trigger at all — the tick is. This pins that decoupling.
    func testPrompt_notRaisedBySavingAnAlreadyFinishedTake() throws {
        var take = reminderTake(prose: "Ring the surveyor back", items: [("scan it", false)])
        let vm = try makeVM([take])
        take.setAllItemsComplete(true)
        vm.noteTasksCompleted(take)
        vm.clearTasksCompletedNotice()

        // Saving an already-finished Take must not re-raise it. Saving no longer triggers the
        // prompt at all — the TICK does (owner 2026-08-11) — so this is now guarding that the
        // decoupling holds rather than a transition check inside `save`.
        take.isImportant = true
        vm.save(take)
        XCTAssertNil(vm.tasksCompletedTakeID)
    }

    /// A one-shot on a PURE checklist is already auto-skipped by the scheduler, so asking
    /// about a reminder that will never sound again would be noise.
    func testPrompt_notRaisedForAPureChecklistOneShot() throws {
        let take = reminderTake(prose: nil, items: [("Milk", false)])
        let vm = try makeVM([take])
        var done = take
        done.setAllItemsComplete(true)
        vm.noteTasksCompleted(done)
        XCTAssertNil(vm.tasksCompletedTakeID)
    }

    /// …but the same pure checklist REPEATING still fires forever, so the prompt is exactly
    /// where the missing lever is.
    func testPrompt_raisedForAPureChecklistRepeating() throws {
        let take = reminderTake(prose: nil, items: [("Milk", false)], recurrence: .weekly)
        let vm = try makeVM([take])
        var done = take
        done.setAllItemsComplete(true)
        vm.noteTasksCompleted(done)
        XCTAssertEqual(vm.tasksCompletedTakeID, take.id)
    }

    func testPrompt_notRaisedWhenThereIsNoReminder() throws {
        let take = Take(blocks: [.textLine("shopping"), .checkItem("Milk", isComplete: false)])
        let vm = try makeVM([take])
        var done = take
        done.setAllItemsComplete(true)
        vm.noteTasksCompleted(done)
        XCTAssertNil(vm.tasksCompletedTakeID)
    }

    /// "Stop" REMOVES the reminder (owner 2026-08-13). Muting it left the date on the card with
    /// a crossed-out bell, which reads as a reminder that still exists.
    func testStopReminding_removesTheReminder_andKeepsTheTake() throws {
        let take = reminderTake(prose: "Ring the surveyor back",
                                items: [("scan it", false)], recurrence: .weekly)
        let vm = try makeVM([take])
        var done = take
        done.setAllItemsComplete(true)
        vm.save(done)                    // stored, so the store-backed path applies
        vm.noteTasksCompleted(done)

        vm.stopRemindingForCompletedTake()
        let stored = try XCTUnwrap(vm.store.take(id: take.id))
        XCTAssertNil(stored.timeReminder, "the reminder is gone, not merely muted")
        XCTAssertEqual(stored.plainText, take.plainText, "the Take itself is untouched")
        XCTAssertNil(vm.tasksCompletedTakeID)
    }

    // MARK: - No-op save (2026-09-03, D-250)

    /// THE REPRODUCTION. Saving a Take that has not changed must NOT bump `modifiedAt`.
    /// Opening a Take to read it and tapping away runs the same commit path, and the bump
    /// desynchronised the Take from its cloud copy — the next pull then raised a conflict
    /// between two versions with identical text and offered to delete one.
    func testSave_unchangedTake_doesNotBumpModifiedAt() throws {
        let original = Take(createdAt: Date(timeIntervalSince1970: 1_000),
                            modifiedAt: Date(timeIntervalSince1970: 2_000),
                            blocks: [.textLine("https://youtu.be/wt9N42GDdqM")])
        let store = InMemoryTakeStore()
        try store.upsert(original)
        let vm = DailiesViewModel(store: store, reminders: ReminderScheduler(center: QuietCenter()))

        vm.save(original)          // committed without a single character changing

        let after = try store.take(id: original.id)
        XCTAssertEqual(after?.modifiedAt, original.modifiedAt,
            "A save that changed nothing bumped modifiedAt — that desynchronises the Take from its cloud copy and raises a conflict over two identical versions.")
        XCTAssertEqual(after, original,
            "An unchanged save must leave the stored Take byte-identical.")
    }

    /// The healthy path is untouched: a REAL edit still bumps `modifiedAt`, or the sync
    /// engine would never push it (push selects on the watermark).
    func testSave_editedTake_stillBumpsModifiedAt() throws {
        let original = Take(createdAt: Date(timeIntervalSince1970: 1_000),
                            modifiedAt: Date(timeIntervalSince1970: 2_000),
                            blocks: [.textLine("before")])
        let store = InMemoryTakeStore()
        try store.upsert(original)
        let vm = DailiesViewModel(store: store, reminders: ReminderScheduler(center: QuietCenter()))

        var edited = original
        edited.blocks = [.textLine("after")]
        vm.save(edited)

        let after = try store.take(id: original.id)
        XCTAssertGreaterThan(after!.modifiedAt, original.modifiedAt,
            "A real edit must bump modifiedAt — push selects by `modifiedAt > lastSync`, so an unbumped edit never leaves the device.")
        XCTAssertEqual(after?.plainText, "after")
    }

    /// A seeded Take that is merely OPENED keeps its seed flag: opening is not a first
    /// edit. The flag still clears when something actually changes.
    func testSave_unchangedSeededTake_keepsSeedFlagAndDate() throws {
        var seeded = Take(createdAt: Date(timeIntervalSince1970: 1_000),
                          modifiedAt: Date(timeIntervalSince1970: 2_000),
                          blocks: [.textLine("seed")])
        seeded.isSeeded = true
        let store = InMemoryTakeStore()
        try store.upsert(seeded)
        let vm = DailiesViewModel(store: store, reminders: ReminderScheduler(center: QuietCenter()))

        vm.save(seeded)

        let after = try store.take(id: seeded.id)
        XCTAssertEqual(after?.isSeeded, true, "Opening a seeded Take is not a first edit; the flag must survive.")
        XCTAssertEqual(after?.modifiedAt, seeded.modifiedAt)
    }
}
#endif
