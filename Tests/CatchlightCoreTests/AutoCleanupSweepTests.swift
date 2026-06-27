//
//  AutoCleanupSweepTests.swift
//  CatchlightCoreTests — DailiesViewModel.runAutoCleanup behaviour (owner 2026-06-21)
//
//  The eligibility RULE is unit-tested in TakeAutoCleanupTests; this covers the SWEEP:
//  it deletes eligible Takes, and — the fix here — a failed delete is SURFACED (not
//  swallowed) and does not de-index Spotlight / cancel the reminder for a Take that is
//  still present. App-target only (DailiesViewModel lives there).
//

#if canImport(Catchlight)
import XCTest
import UserNotifications
@testable import Catchlight
@testable import CatchlightCore

/// Records Spotlight de-index calls so the test can assert a failed delete does NOT
/// drop the Take from the OS index.
private final class SpotlightSpy: SpotlightIndexing, @unchecked Sendable {
    private(set) var deindexed: [UUID] = []
    func index(_ take: Take) {}
    func deindex(takeID: UUID) { deindexed.append(takeID) }
    func deindexAll() {}
}

/// A notification centre that records nothing real — keeps `cancelReminder` off the
/// live `UNUserNotificationCenter` during the sweep.
private final class SilentCenter: NotificationScheduling {
    func add(_ request: UNNotificationRequest) {}
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
}

/// Wraps an `InMemoryTakeStore`, forwarding everything, but throws on `delete` so the
/// sweep's failure path can be exercised.
private final class ThrowingDeleteStore: TakeStore {
    let inner = InMemoryTakeStore()
    func upsert(_ take: Take) throws { try inner.upsert(take) }
    func delete(id: UUID) throws { throw StorageError.notFound(id) }   // always fails
    func take(id: UUID) throws -> Take? { try inner.take(id: id) }
    func allTakes() throws -> [Take] { try inner.allTakes() }
    func takesModified(since date: Date?) throws -> [Take] { try inner.takesModified(since: date) }
    func search(_ query: String) throws -> [Take] { try inner.search(query) }
    func upsert(_ sequence: CatchlightSequence) throws { try inner.upsert(sequence) }
    func sequence(id: UUID) throws -> CatchlightSequence? { try inner.sequence(id: id) }
    func allSequences() throws -> [CatchlightSequence] { try inner.allSequences() }
    func deleteSequence(id: UUID) throws { try inner.deleteSequence(id: id) }
    func currentObie() throws -> Take? { try inner.currentObie() }
    func setObie(id: UUID, replaceExisting: Bool) throws { try inner.setObie(id: id, replaceExisting: replaceExisting) }
    func lastSyncDate() -> Date? { inner.lastSyncDate() }
    func setLastSyncDate(_ date: Date) { inner.setLastSyncDate(date) }
    func tombstones() throws -> [Tombstone] { try inner.tombstones() }
    func purgeTombstones(ids: [UUID]) throws { try inner.purgeTombstones(ids: ids) }
}

@MainActor
final class AutoCleanupSweepTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_000_000)
    private var twoDaysLater: Date { base.addingTimeInterval(2 * 24 * 60 * 60) }
    private let day: TimeInterval = 24 * 60 * 60

    /// A finished, note-free, old Take — eligible for cleanup.
    private func eligibleTake() -> Take {
        Take(modifiedAt: base, blocks: [.checkItem("milk", isComplete: true)])
    }

    private func makeVM(store: TakeStore, spotlight: SpotlightSpy) -> DailiesViewModel {
        DailiesViewModel(store: store,
                         spotlight: spotlight,
                         reminders: ReminderScheduler(center: SilentCenter(), now: { self.base }))
    }

    func testSweep_deletesEligible_andReportsCount_noError() throws {
        let store = InMemoryTakeStore()
        try store.upsert(eligibleTake())
        try store.upsert(Take(modifiedAt: base, blocks: [.textLine("a kept note")]))   // protected
        let spotlight = SpotlightSpy()
        let vm = makeVM(store: store, spotlight: spotlight)

        let removed = vm.runAutoCleanup(olderThan: day, now: twoDaysLater)

        XCTAssertEqual(removed, 1, "only the finished, note-free Take is swept")
        XCTAssertEqual(try store.allTakes().count, 1, "the note survives")
        XCTAssertEqual(spotlight.deindexed.count, 1, "the deleted Take is de-indexed")
        XCTAssertNil(vm.lastError)
    }

    func testSweep_deleteFailure_isSurfaced_andLeavesTakeAndIndexUntouched() throws {
        let store = ThrowingDeleteStore()
        try store.upsert(eligibleTake())
        let spotlight = SpotlightSpy()
        let vm = makeVM(store: store, spotlight: spotlight)

        let removed = vm.runAutoCleanup(olderThan: day, now: twoDaysLater)

        XCTAssertEqual(removed, 0, "nothing was actually deleted")
        XCTAssertEqual(try store.allTakes().count, 1, "the Take remains in the store")
        XCTAssertTrue(spotlight.deindexed.isEmpty,
                      "a failed delete must NOT de-index the still-present Take")
        XCTAssertNotNil(vm.lastError, "the failure is surfaced, not swallowed")
    }

    func testSweep_neverWindow_isNoOp() {
        let store = InMemoryTakeStore()
        let vm = makeVM(store: store, spotlight: SpotlightSpy())
        XCTAssertEqual(vm.runAutoCleanup(olderThan: nil, now: twoDaysLater), 0)
        XCTAssertNil(vm.lastError)
    }
}
#endif
