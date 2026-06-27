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
}
#endif
