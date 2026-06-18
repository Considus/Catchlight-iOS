//
//  ReminderSchedulerTests.swift
//  CatchlightCoreTests — Task 7.2, revised for the 2026-06-10 remediation
//
//  Covers `ReminderScheduler` via the `NotificationScheduling` seam (default is
//  `UNUserNotificationCenter.current()`; tests inject a fake). No real
//  UNNotificationCenter calls; no permission prompt; no real notifications fire.
//
//  2026-06-10 changes covered here:
//    • `NotificationScheduling` gained `requestAuthorization(options:)` — the
//      scheduler's own `requestAuthorization()` now goes through the seam.
//    • `scheduleReminder` REFUSES past-dated reminders (injectable `now:`).
//    • The calendar trigger pins `components.timeZone` (absolute-instant
//      semantics — reminders no longer drift when the device changes zones).
//
//  iOS-only — gated on `canImport(Catchlight)`.
//

#if canImport(Catchlight)
import XCTest
import UserNotifications
@testable import Catchlight
@testable import CatchlightCore

private final class FakeNotificationCenter: NotificationScheduling {
    private(set) var added: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [[String]] = []
    private(set) var authorizationRequests: [UNAuthorizationOptions] = []
    var authorizationResult: Result<Bool, Error> = .success(true)

    func add(_ request: UNNotificationRequest) {
        added.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
        added.removeAll { identifiers.contains($0.identifier) }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequests.append(options)
        return try authorizationResult.get()
    }
}

final class ReminderSchedulerTests: XCTestCase {

    /// Fixed, injected "now" — no wall-clock dependence.
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private var center: FakeNotificationCenter!
    private var scheduler: ReminderScheduler!

    override func setUp() {
        super.setUp()
        center = FakeNotificationCenter()
        scheduler = ReminderScheduler(center: center, now: { [now] in now })
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
        return Take(id: id, blocks: [.textLine(body)], timeReminder: reminder)
    }

    // MARK: - Scheduling

    func testSchedule_futureDate_addsRequestWithIdentifier() {
        let take = takeWithReminder(at: now.addingTimeInterval(3600))
        scheduler.scheduleReminder(for: take)
        XCTAssertEqual(center.added.count, 1)
        XCTAssertEqual(center.added.first?.identifier, take.timeReminder?.notificationIdentifier)
    }

    func testSchedule_identifierMatchesTimeReminder() {
        let id = "custom-id-123"
        let take = takeWithReminder(at: now.addingTimeInterval(60), identifier: id)
        scheduler.scheduleReminder(for: take)
        XCTAssertEqual(center.added.first?.identifier, id)
    }

    func testSchedule_takeWithoutReminder_addsNothing() {
        let take = Take(blocks: [.textLine("no reminder")])
        scheduler.scheduleReminder(for: take)
        XCTAssertEqual(center.added.count, 0)
    }

    /// Model C (owner 2026-06-18): a future-dated "when" with its alarm OFF is a silent
    /// planner placement — it must NOT schedule a notification.
    func testSchedule_alarmDisabled_addsNothing() {
        let id = UUID()
        let reminder = TimeReminder(scheduledDate: now.addingTimeInterval(3600),
                                    notificationIdentifier: id.uuidString,
                                    alarmEnabled: false)
        let take = Take(id: id, blocks: [.textLine("silent plan")], timeReminder: reminder)
        scheduler.scheduleReminder(for: take)
        XCTAssertEqual(center.added.count, 0,
                       "an alarm-off reminder must not reach the notification center")
    }

    /// Model C (owner 2026-06-18): an ALL-DAY "when" with its alarm ON fires at the
    /// scheduler's default hour, NOT the (meaningless) stored time component.
    func testSchedule_allDay_firesAtDefaultHour() throws {
        // Stored time is deliberately odd (the all-day date component is what matters).
        let oddTime = Calendar.current.date(bySettingHour: 3, minute: 17, second: 0,
                                            of: now.addingTimeInterval(48 * 3600))!
        let id = UUID()
        let reminder = TimeReminder(scheduledDate: oddTime,
                                    notificationIdentifier: id.uuidString,
                                    isAllDay: true)
        let take = Take(id: id, blocks: [.textLine("all day")], timeReminder: reminder)
        scheduler.scheduleReminder(for: take)

        let request = try XCTUnwrap(center.added.first)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, ReminderScheduler.allDayFireHour,
                       "an all-day alarm fires at the default hour, not the stored time")
        XCTAssertEqual(trigger.dateComponents.minute, 0)
    }

    /// Reminders are Time Sensitive (owner 2026-06-18) so they break through Focus /
    /// Do Not Disturb, like Apple's Reminders. Requires the entitlement (project.yml).
    func testSchedule_isTimeSensitive() {
        let take = takeWithReminder(at: now.addingTimeInterval(60))
        scheduler.scheduleReminder(for: take)
        XCTAssertEqual(center.added.first?.content.interruptionLevel, .timeSensitive)
    }

    /// The Take's text is the notification TITLE (content-first, owner 2026-06-18) —
    /// not the body and not the app name. The "when" rides the subtitle.
    func testSchedule_setsCategoryAndTitle() {
        let take = takeWithReminder(at: now.addingTimeInterval(60),
                                    body: "buy milk and bread")
        scheduler.scheduleReminder(for: take)
        let request = try? XCTUnwrap(center.added.first)
        XCTAssertEqual(request?.content.categoryIdentifier, ReminderScheduler.categoryIdentifier)
        XCTAssertEqual(request?.content.title, "buy milk and bread")
        XCTAssertFalse(request?.content.subtitle.isEmpty ?? true,
                       "the scheduled 'when' should populate the subtitle")
    }

    /// The title is truncated at 100 characters to keep notification payloads small
    /// (and to limit how much Take content surfaces outside the app boundary).
    func testSchedule_longTitleTruncatedAt100Chars() {
        let longBody = String(repeating: "a", count: 250)
        let take = takeWithReminder(at: now.addingTimeInterval(60), body: longBody)
        scheduler.scheduleReminder(for: take)
        XCTAssertEqual(center.added.first?.content.title.count, 100)
    }

    // MARK: - Past-date refusal (2026-06-10)

    /// A past-dated reminder is REFUSED at the boundary: no `add()` call. A
    /// non-repeating calendar trigger in the past never fires, so scheduling it
    /// would leave the model holding a reminder that silently never delivers.
    func testSchedule_pastDate_isRefused() {
        let take = takeWithReminder(at: now.addingTimeInterval(-3600))
        scheduler.scheduleReminder(for: take)
        XCTAssertEqual(center.added.count, 0,
                       "past-dated reminders must not reach the notification center")
    }

    /// Boundary: a reminder exactly AT `now` is also refused (the guard is
    /// strictly `scheduledDate > now`).
    func testSchedule_exactlyNow_isRefused() {
        let take = takeWithReminder(at: now)
        scheduler.scheduleReminder(for: take)
        XCTAssertEqual(center.added.count, 0)
    }

    // MARK: - Time-zone pinning (2026-06-10)

    /// The calendar trigger pins `timeZone` so the date components are evaluated
    /// in the zone they were computed in — absolute-instant semantics; the
    /// reminder no longer drifts when a travelling user changes zones.
    func testSchedule_triggerPinsTimeZone() throws {
        let take = takeWithReminder(at: now.addingTimeInterval(3600))
        scheduler.scheduleReminder(for: take)

        let request = try XCTUnwrap(center.added.first)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.timeZone, TimeZone.current,
                       "components.timeZone must be pinned, not left floating")
        XCTAssertFalse(trigger.repeats)
    }

    // MARK: - Authorization (through the seam, 2026-06-10)

    func testRequestAuthorization_goesThroughSeam_andReturnsGrant() async {
        center.authorizationResult = .success(true)
        let granted = await scheduler.requestAuthorization()
        XCTAssertTrue(granted)
        XCTAssertEqual(center.authorizationRequests.count, 1)
        XCTAssertEqual(center.authorizationRequests.first, [.alert, .sound, .badge])
    }

    func testRequestAuthorization_deniedOrThrowing_returnsFalse() async {
        center.authorizationResult = .success(false)
        let denied = await scheduler.requestAuthorization()
        XCTAssertFalse(denied)

        struct AuthError: Error {}
        center.authorizationResult = .failure(AuthError())
        let errored = await scheduler.requestAuthorization()
        XCTAssertFalse(errored, "an authorization error must map to a calm false")
    }

    // MARK: - Cancellation

    func testCancel_removesByIdentifier() {
        let take = takeWithReminder(at: now.addingTimeInterval(60))
        scheduler.scheduleReminder(for: take)
        scheduler.cancelReminder(for: take)
        XCTAssertEqual(center.added.count, 0)
        XCTAssertEqual(center.removedIdentifiers.last,
                       [take.timeReminder!.notificationIdentifier])
    }

    func testCancel_takeWithoutReminder_isNoOp() {
        let take = Take(blocks: [.textLine("x")])
        scheduler.cancelReminder(for: take)
        XCTAssertEqual(center.removedIdentifiers.count, 0)
    }

    // MARK: - Reschedule

    /// Reschedule cancels the prior request and adds a new one — net effect is
    /// exactly one pending request for the same identifier, never a duplicate.
    func testReschedule_replacesNotDuplicates() {
        let id = UUID()
        var take = Take(id: id, blocks: [.textLine("x")], timeReminder: TimeReminder(
            scheduledDate: now.addingTimeInterval(60),
            notificationIdentifier: id.uuidString
        ))
        scheduler.scheduleReminder(for: take)
        take.timeReminder?.scheduledDate = now.addingTimeInterval(3600)
        scheduler.reschedule(for: take)
        XCTAssertEqual(center.added.count, 1, "Only the latest request should be pending")
        XCTAssertEqual(center.added.first?.identifier, id.uuidString)
        XCTAssertEqual(center.removedIdentifiers.last, [id.uuidString])
    }
}
#endif
