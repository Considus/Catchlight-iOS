//
//  ReminderSchedulerTests.swift
//  CatchlightCoreTests — Task 7.2
//
//  Covers `ReminderScheduler` via the `NotificationScheduling` seam added in
//  Task 7.2 (default is `UNUserNotificationCenter.current()`; tests inject a
//  fake). No real UNNotificationCenter calls; no permission prompt; no real
//  notifications fire.
//
//  iOS-only — gated on `canImport(Catchlight)`.
//
//  PAST-DATE BEHAVIOUR: the current implementation has NO guard against past
//  scheduled dates. `UNCalendarNotificationTrigger` silently drops past
//  triggers, but the scheduler still calls `center.add(_:)`. The test below
//  documents this current behaviour; a follow-up could add an explicit guard.
//

#if canImport(Catchlight)
import XCTest
import UserNotifications
@testable import Catchlight
@testable import CatchlightCore

private final class FakeNotificationCenter: NotificationScheduling {
    private(set) var added: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [[String]] = []

    func add(_ request: UNNotificationRequest) {
        added.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
        added.removeAll { identifiers.contains($0.identifier) }
    }
}

final class ReminderSchedulerTests: XCTestCase {

    private var center: FakeNotificationCenter!
    private var scheduler: ReminderScheduler!

    override func setUp() {
        super.setUp()
        center = FakeNotificationCenter()
        scheduler = ReminderScheduler(center: center)
    }

    override func tearDown() {
        scheduler = nil
        center = nil
        super.tearDown()
    }

    private func takeWithReminder(at date: Date,
                                  identifier: String? = nil,
                                  body: String = "remember") -> Take {
        let id = UUID()
        let reminder = TimeReminder(
            scheduledDate: date,
            notificationIdentifier: identifier ?? id.uuidString
        )
        return Take(id: id, bodyText: body, timeReminder: reminder)
    }

    // MARK: - Scheduling

    func testSchedule_futureDate_addsRequestWithIdentifier() {
        let take = takeWithReminder(at: Date().addingTimeInterval(3600))
        scheduler.scheduleReminder(for: take)
        XCTAssertEqual(center.added.count, 1)
        XCTAssertEqual(center.added.first?.identifier, take.timeReminder?.notificationIdentifier)
    }

    func testSchedule_identifierMatchesTimeReminder() {
        let id = "custom-id-123"
        let take = takeWithReminder(at: Date().addingTimeInterval(60), identifier: id)
        scheduler.scheduleReminder(for: take)
        XCTAssertEqual(center.added.first?.identifier, id)
    }

    func testSchedule_takeWithoutReminder_addsNothing() {
        let take = Take(bodyText: "no reminder")
        scheduler.scheduleReminder(for: take)
        XCTAssertEqual(center.added.count, 0)
    }

    func testSchedule_setsCategoryAndBody() {
        let take = takeWithReminder(at: Date().addingTimeInterval(60),
                                    body: "buy milk and bread")
        scheduler.scheduleReminder(for: take)
        let request = try? XCTUnwrap(center.added.first)
        XCTAssertEqual(request?.content.categoryIdentifier, ReminderScheduler.categoryIdentifier)
        XCTAssertEqual(request?.content.body, "buy milk and bread")
    }

    /// Body is truncated at 100 characters to keep notification payloads small
    /// (and to limit how much Take content surfaces outside the app boundary).
    func testSchedule_longBodyTruncatedAt100Chars() {
        let longBody = String(repeating: "a", count: 250)
        let take = takeWithReminder(at: Date().addingTimeInterval(60), body: longBody)
        scheduler.scheduleReminder(for: take)
        XCTAssertEqual(center.added.first?.content.body.count, 100)
    }

    /// Documents current behaviour: a past scheduled date STILL produces an
    /// `add()` call (UNCalendarNotificationTrigger then drops it). If the
    /// scheduler ever grows an explicit past-date guard, flip this assertion.
    func testSchedule_pastDate_currentlyStillCallsAdd() {
        let take = takeWithReminder(at: Date().addingTimeInterval(-3600))
        scheduler.scheduleReminder(for: take)
        XCTAssertEqual(center.added.count, 1,
                       "Past-date guard is not implemented. Update this test if that changes.")
    }

    // MARK: - Cancellation

    func testCancel_removesByIdentifier() {
        let take = takeWithReminder(at: Date().addingTimeInterval(60))
        scheduler.scheduleReminder(for: take)
        scheduler.cancelReminder(for: take)
        XCTAssertEqual(center.added.count, 0)
        XCTAssertEqual(center.removedIdentifiers.last,
                       [take.timeReminder!.notificationIdentifier])
    }

    func testCancel_takeWithoutReminder_isNoOp() {
        let take = Take(bodyText: "x")
        scheduler.cancelReminder(for: take)
        XCTAssertEqual(center.removedIdentifiers.count, 0)
    }

    // MARK: - Reschedule

    /// Reschedule cancels the prior request and adds a new one — net effect is
    /// exactly one pending request for the same identifier, never a duplicate.
    func testReschedule_replacesNotDuplicates() {
        let id = UUID()
        var take = Take(id: id, bodyText: "x", timeReminder: TimeReminder(
            scheduledDate: Date().addingTimeInterval(60),
            notificationIdentifier: id.uuidString
        ))
        scheduler.scheduleReminder(for: take)
        take.timeReminder?.scheduledDate = Date().addingTimeInterval(3600)
        scheduler.reschedule(for: take)
        XCTAssertEqual(center.added.count, 1, "Only the latest request should be pending")
        XCTAssertEqual(center.added.first?.identifier, id.uuidString)
        XCTAssertEqual(center.removedIdentifiers.last, [id.uuidString])
    }
}
#endif
