//
//  DailiesViewModelReminderReconcileTests.swift
//  CatchlightAppTests — 2026-07-02 regression follow-up to the mid-point remediation
//
//  Pins the two OWNER-FACING reminder-seam behaviours the remediation fixed at the
//  view-model layer, which PR #97 covered only at the plumbing layer:
//
//    A. "Dismiss" on a reminder must STICK — `applyPendingReminderActions` turns the
//       matching alarm off in the store (a one-shot TIME reminder, or a PLACE
//       reminder's geofence) and leaves a RECURRING series alone. Before the fix the
//       drain guarded on `timeReminder` only, so a dismissed geofence re-armed on
//       every unlock and nagged forever.
//    B. A Take DELETED on another device must have its local notifications CANCELLED —
//       `applyRemoteChanges` clears every id a deleted Take owns. Before the fix the
//       remote-changes hook only reloaded the UI, so the deleted Take's alarm still
//       fired with its decrypted title (stale alarm + privacy leak).
//
//  App-target only (`DailiesViewModel` lives there). Uses an injected recording
//  notification centre so nothing touches the live `UNUserNotificationCenter`.
//

#if canImport(Catchlight)
import XCTest
import UserNotifications
@testable import Catchlight
@testable import CatchlightCore

/// Records the identifiers passed to each removal call so a test can assert what
/// was cancelled, without touching the real notification centre.
private final class RecordingCenter: NotificationScheduling {
    private(set) var added: [UNNotificationRequest] = []
    private(set) var removedPending: [[String]] = []
    private(set) var removedDelivered: [[String]] = []
    func add(_ request: UNNotificationRequest) { added.append(request) }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPending.append(identifiers)
        added.removeAll { identifiers.contains($0.identifier) }
    }
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDelivered.append(identifiers)
    }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    /// Every pending identifier ever removed, flattened.
    var allRemovedPending: Set<String> { Set(removedPending.flatMap { $0 }) }
}

@MainActor
final class DailiesViewModelReminderReconcileTests: XCTestCase {

    private var center: RecordingCenter!
    private var store: InMemoryTakeStore!
    private var vm: DailiesViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        center = RecordingCenter()
        store = InMemoryTakeStore()
        vm = DailiesViewModel(store: store, reminders: ReminderScheduler(center: center))
        // Start each test from an empty deferred-Dismiss queue (app-group defaults).
        _ = PendingReminderActions.drainDismissed()
    }

    override func tearDown() {
        _ = PendingReminderActions.drainDismissed()
        vm = nil; store = nil; center = nil
        super.tearDown()
    }

    private func place(alarmEnabled: Bool = true) -> LocationTrigger {
        LocationTrigger(latitude: 51.5, longitude: -0.1, radiusMetres: 150,
                        triggerOnArrival: true, locationName: "Office", alarmEnabled: alarmEnabled)
    }

    private func timeReminder(id: UUID, recurrence: TimeReminder.Recurrence = .none) -> TimeReminder {
        TimeReminder(scheduledDate: Date(timeIntervalSince1970: 1_780_000_000),
                     notificationIdentifier: id.uuidString, recurrence: recurrence)
    }

    // MARK: - A. Dismiss sticks

    /// A queued PLACE dismissal turns the geofence alarm off in the store (the
    /// exact bug: previously skipped, so it re-armed forever).
    func testApplyPendingReminderActions_placeDismiss_turnsGeofenceOff() throws {
        let id = UUID()
        try store.upsert(Take(id: id, blocks: [.textLine("pick up parcel")],
                              locationReminder: place(alarmEnabled: true)))
        PendingReminderActions.enqueueDismiss(takeID: id.uuidString, isLocation: true)

        vm.applyPendingReminderActions()

        XCTAssertEqual(try store.take(id: id)?.locationReminder?.alarmEnabled, false,
                       "a dismissed place reminder must have its geofence alarm turned off")
    }

    /// A queued TIME dismissal on a one-shot turns its alarm off.
    func testApplyPendingReminderActions_oneShotTimeDismiss_turnsAlarmOff() throws {
        let id = UUID()
        try store.upsert(Take(id: id, blocks: [.textLine("call back")],
                              timeReminder: timeReminder(id: id)))
        PendingReminderActions.enqueueDismiss(takeID: id.uuidString)

        vm.applyPendingReminderActions()

        XCTAssertEqual(try store.take(id: id)?.timeReminder?.alarmEnabled, false)
    }

    /// A RECURRING series is left entirely alone (Dismiss clears only the current
    /// occurrence's OS alarm; the series keeps firing).
    func testApplyPendingReminderActions_recurringDismiss_leavesSeriesArmed() throws {
        let id = UUID()
        try store.upsert(Take(id: id, blocks: [.textLine("daily standup")],
                              timeReminder: timeReminder(id: id, recurrence: .daily)))
        PendingReminderActions.enqueueDismiss(takeID: id.uuidString)

        vm.applyPendingReminderActions()

        XCTAssertEqual(try store.take(id: id)?.timeReminder?.alarmEnabled, true,
                       "a recurring reminder's alarm must stay on after Dismiss")
    }

    /// The place and time paths don't cross: dismissing the place leaves a
    /// co-present time reminder untouched (kind-aware queue).
    func testApplyPendingReminderActions_placeDismiss_leavesCoPresentTimeReminder() throws {
        let id = UUID()
        var take = Take(id: id, blocks: [.textLine("errand")], timeReminder: timeReminder(id: id))
        take.locationReminder = place(alarmEnabled: true)
        try store.upsert(take)
        PendingReminderActions.enqueueDismiss(takeID: id.uuidString, isLocation: true)

        vm.applyPendingReminderActions()

        let reloaded = try XCTUnwrap(try store.take(id: id))
        XCTAssertEqual(reloaded.locationReminder?.alarmEnabled, false, "place off")
        XCTAssertEqual(reloaded.timeReminder?.alarmEnabled, true, "time reminder untouched")
    }

    // MARK: - B. Remote deletion cancels notifications

    /// `applyRemoteChanges` cancels every notification a remotely-deleted Take owns
    /// (so its alarm can't fire with the deleted Take's title after the deletion syncs).
    func testApplyRemoteChanges_remoteDeletion_cancelsNotifications() throws {
        let id = UUID()
        var report = SyncReport()
        report.deletedLocally = [id]

        vm.applyRemoteChanges(report)

        XCTAssertTrue(center.allRemovedPending.contains(id.uuidString),
                      "the deleted Take's base alarm id must be cancelled")
        XCTAssertTrue(center.removedDelivered.flatMap { $0 }.contains(id.uuidString),
                      "already-delivered banners for the deleted Take must be cleared too")
    }

    /// An APPLIED remote edit that carries a reminder re-registers its alarm
    /// (reconcile-then-reload), so a reminder added on another device rings here.
    func testApplyRemoteChanges_appliedReminder_isScheduled() throws {
        // The VM's FIRST-EVER reminder reconcile takes an async notification-auth
        // branch (`requestAuthorization` then schedule) — it flips
        // `didRequestNotificationAuth` synchronously but schedules on a detached
        // Task. Prime past it with one applied reminder so the assertion below
        // targets the deterministic SYNCHRONOUS scheduling path.
        let primer = UUID()
        try store.upsert(Take(id: primer, blocks: [.textLine("primer")],
                              timeReminder: TimeReminder(scheduledDate: Date().addingTimeInterval(3600),
                                                         notificationIdentifier: primer.uuidString)))
        var prime = SyncReport(); prime.applied = [primer]
        vm.applyRemoteChanges(prime)

        let id = UUID()
        try store.upsert(Take(id: id, blocks: [.textLine("remote reminder")],
                              timeReminder: TimeReminder(scheduledDate: Date().addingTimeInterval(3600),
                                                         notificationIdentifier: id.uuidString)))
        var report = SyncReport(); report.applied = [id]
        vm.applyRemoteChanges(report)

        XCTAssertTrue(center.added.contains { $0.identifier == id.uuidString },
                      "an applied remote reminder must be scheduled locally")
    }
}
#endif
