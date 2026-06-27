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
import CoreLocation
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
        // Cancel clears the one-shot id AND the whole recurring window (`<id>#0…`), so a
        // single cancel works whichever kind the Take was (owner 2026-06-21).
        XCTAssertEqual(center.removedIdentifiers.last,
                       ReminderScheduler.allIdentifiers(base: take.timeReminder!.notificationIdentifier))
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
        // Reschedule cancels via the full id set (one-shot id + recurring window + snooze + catch-up).
        XCTAssertEqual(center.removedIdentifiers.last, ReminderScheduler.allIdentifiers(base: id.uuidString))
    }

    // MARK: - Identifier namespaces (owner 2026-06-21)

    /// The periodic-rebuild clear scope (base + window) must EXCLUDE the snooze and
    /// catch-up ids, so a rebuild can never clobber a pending snooze; the full cancel set
    /// must INCLUDE them, so an explicit edit/delete clears everything.
    func testIdentifierNamespaces_rebuildScopeExcludesSnoozeAndCatchUp() {
        let base = "ABC"
        let windowAndBase = ReminderScheduler.windowAndBaseIdentifiers(base: base)
        let all = ReminderScheduler.allIdentifiers(base: base)
        let snooze = ReminderScheduler.snoozeIdentifier(base: base)
        let catchUp = ReminderScheduler.catchUpIdentifier(base: base)

        XCTAssertFalse(windowAndBase.contains(snooze))
        XCTAssertFalse(windowAndBase.contains(catchUp))
        XCTAssertTrue(all.contains(snooze))
        XCTAssertTrue(all.contains(catchUp))
        XCTAssertTrue(all.contains(base))
        XCTAssertEqual(snooze, "ABC#snooze")
        XCTAssertEqual(catchUp, "ABC#today")
    }

    // MARK: - Recurring window + global budget (owner 2026-06-21)

    private func recurringTake(_ rec: TimeReminder.Recurrence, at date: Date, body: String = "x") -> Take {
        let id = UUID()
        return Take(id: id, blocks: [.textLine(body)],
                    timeReminder: TimeReminder(scheduledDate: date,
                                               notificationIdentifier: id.uuidString,
                                               recurrence: rec))
    }

    /// A repeating reminder schedules a rolling window of individually-cancellable alarms.
    func testSchedule_recurring_addsWindowOfOccurrences() {
        let take = recurringTake(.daily, at: now.addingTimeInterval(3600))
        scheduler.scheduleReminder(for: take)
        XCTAssertEqual(center.added.count, ReminderScheduler.recurrenceWindow)
        let base = take.timeReminder!.notificationIdentifier
        XCTAssertEqual(center.added.first?.identifier,
                       ReminderScheduler.windowIdentifier(base: base, index: 0))
    }

    /// `rescheduleAll` keeps the pending set within the global cap, favouring the soonest
    /// occurrences across every reminder — so a fleet can't silently overflow iOS's 64.
    func testRescheduleAll_capsAtGlobalBudget() {
        // 6 daily reminders × a 12-deep window = 72 planned > the 60 budget.
        let takes = (0..<6).map { recurringTake(.daily, at: now.addingTimeInterval(Double(3600 + $0 * 60))) }
        scheduler.rescheduleAll(takes: takes)
        XCTAssertEqual(center.added.count, ReminderScheduler.maxPendingAlarms,
                       "the pending set is capped at the global budget")
    }

    /// `rescheduleAll` clears each reminder's base+window but NOT its snooze id, so a
    /// pending snooze survives an app-open rebuild (the R3 fix).
    func testRescheduleAll_preservesPendingSnooze() {
        let take = recurringTake(.daily, at: now.addingTimeInterval(3600))
        let base = take.timeReminder!.notificationIdentifier
        // A snooze is pending under the dedicated namespace.
        scheduler.scheduleSnooze(title: "t",
                                 identifier: ReminderScheduler.snoozeIdentifier(base: base),
                                 fireAt: now.addingTimeInterval(1800),
                                 dueText: "Today at 3 PM")
        XCTAssertTrue(center.added.contains { $0.identifier == ReminderScheduler.snoozeIdentifier(base: base) })

        scheduler.rescheduleAll(takes: [take])
        XCTAssertTrue(center.added.contains { $0.identifier == ReminderScheduler.snoozeIdentifier(base: base) },
                      "the rebuild must not clobber a pending snooze")
    }

    // MARK: - All-day same-day catch-up (R5, owner 2026-06-21)

    /// An ALL-DAY reminder for TODAY whose default 9am fire time has already passed fires a
    /// prompt "catch-up" nudge (under the `#today` id) instead of being silently dropped.
    func testSchedule_allDayToday_pastDefaultHour_firesCatchUp() throws {
        // A "now" at 2pm, with the all-day reminder dated the same day → 9am is past.
        let nineToday = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        let twoPM = nineToday.addingTimeInterval(5 * 3600)
        let s = ReminderScheduler(center: center, now: { twoPM })
        let id = UUID()
        let take = Take(id: id, blocks: [.textLine("all day, set late")],
                        timeReminder: TimeReminder(scheduledDate: nineToday,   // same day as twoPM
                                                   notificationIdentifier: id.uuidString,
                                                   isAllDay: true))
        s.scheduleReminder(for: take)

        let request = try XCTUnwrap(center.added.first)
        XCTAssertEqual(request.identifier, ReminderScheduler.catchUpIdentifier(base: id.uuidString))
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, ReminderScheduler.allDayLateLeadSeconds, accuracy: 0.5)
    }

    /// An all-day reminder dated a PAST day (not today) is still refused — no catch-up.
    func testSchedule_allDayYesterday_isRefused() {
        let yesterday = now.addingTimeInterval(-26 * 3600)
        let id = UUID()
        let take = Take(id: id, blocks: [.textLine("stale all-day")],
                        timeReminder: TimeReminder(scheduledDate: yesterday,
                                                   notificationIdentifier: id.uuidString,
                                                   isAllDay: true))
        scheduler.scheduleReminder(for: take)
        XCTAssertEqual(center.added.count, 0)
    }

    // MARK: - Location reminders (owner 2026-06-23)

    private func takeWithLocation(arrival: Bool, radius: Double = 150, name: String? = "Home",
                                  lat: Double = 51.5, lon: Double = -0.12,
                                  alarmEnabled: Bool = true) -> Take {
        let loc = LocationTrigger(latitude: lat, longitude: lon, radiusMetres: radius,
                                  triggerOnArrival: arrival, locationName: name,
                                  alarmEnabled: alarmEnabled)
        return Take(id: UUID(), blocks: [.textLine("water the plants")], locationReminder: loc)
    }

    func testScheduleLocation_arrival_addsEntryGeofenceWithLocId() throws {
        let take = takeWithLocation(arrival: true)
        scheduler.scheduleLocationReminder(for: take)

        let request = try XCTUnwrap(center.added.first)
        XCTAssertEqual(request.identifier, ReminderScheduler.locationIdentifier(base: take.id.uuidString))
        let trigger = try XCTUnwrap(request.trigger as? UNLocationNotificationTrigger)
        let region = try XCTUnwrap(trigger.region as? CLCircularRegion)
        XCTAssertTrue(region.notifyOnEntry)
        XCTAssertFalse(region.notifyOnExit)
        XCTAssertEqual(region.center.latitude, 51.5, accuracy: 0.0001)
        XCTAssertEqual(region.radius, 150, accuracy: 0.5)
        XCTAssertEqual(request.content.title, "water the plants")
    }

    func testScheduleLocation_departure_setsExitOnly() throws {
        scheduler.scheduleLocationReminder(for: takeWithLocation(arrival: false))
        let trigger = try XCTUnwrap(center.added.first?.trigger as? UNLocationNotificationTrigger)
        let region = try XCTUnwrap(trigger.region as? CLCircularRegion)
        XCTAssertFalse(region.notifyOnEntry)
        XCTAssertTrue(region.notifyOnExit)
    }

    func testScheduleLocation_radiusBelowFloor_isClamped() throws {
        scheduler.scheduleLocationReminder(for: takeWithLocation(arrival: true, radius: 20))
        let trigger = try XCTUnwrap(center.added.first?.trigger as? UNLocationNotificationTrigger)
        let region = try XCTUnwrap(trigger.region as? CLCircularRegion)
        XCTAssertEqual(region.radius, ReminderScheduler.minGeofenceRadius, accuracy: 0.5)
    }

    func testScheduleLocation_noLocationReminder_addsNothing() {
        scheduler.scheduleLocationReminder(for: Take(blocks: [.textLine("plain")]))
        XCTAssertEqual(center.added.count, 0)
    }

    /// Model-C parity (owner 2026-06-27): a location reminder with its alarm OFF is a silent
    /// place tag — it registers NO geofence.
    func testScheduleLocation_alarmDisabled_addsNothing() {
        scheduler.scheduleLocationReminder(for: takeWithLocation(arrival: true, alarmEnabled: false))
        XCTAssertEqual(center.added.count, 0,
                       "a silent location reminder must not register a geofence")
    }

    /// The app-open rebuild also skips silent location reminders, so they don't eat the
    /// iOS 20-region budget.
    func testRescheduleAll_skipsSilentLocation() {
        let silent = takeWithLocation(arrival: true, alarmEnabled: false)
        let firing = takeWithLocation(arrival: true, alarmEnabled: true)
        scheduler.rescheduleAll(takes: [silent, firing])
        let added = center.added.map(\.identifier)
        XCTAssertFalse(added.contains(ReminderScheduler.locationIdentifier(base: silent.id.uuidString)))
        XCTAssertTrue(added.contains(ReminderScheduler.locationIdentifier(base: firing.id.uuidString)))
    }

    func testCancel_clearsLocationId() {
        let take = takeWithLocation(arrival: true)
        scheduler.scheduleLocationReminder(for: take)
        scheduler.cancelReminder(for: take)
        XCTAssertEqual(center.added.count, 0)
        XCTAssertTrue(center.removedIdentifiers.flatMap { $0 }
            .contains(ReminderScheduler.locationIdentifier(base: take.id.uuidString)))
    }
}
#endif
