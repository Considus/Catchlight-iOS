//
//  ReminderScheduler.swift
//  Catchlight (iOS app target)
//
//  Time-based reminders via UNUserNotificationCenter (Phase 5 brief §8). The
//  notification body is the ONLY place Take content appears outside the encrypted
//  app boundary — an accepted, user-chosen risk documented in the threat model.
//
//  LOCATION-BASED REMINDERS ARE NOT IMPLEMENTED (v1.0). No Core Location import, no
//  UNLocationNotificationTrigger. The `LocationTrigger` type exists in the data
//  model for v1.1 only (brief §8.4).
//
//  TESTABILITY (Task 7.2): the dependency on `UNUserNotificationCenter` is hidden
//  behind the `NotificationScheduling` protocol so unit tests can inject a fake
//  centre and inspect the queue of pending requests without firing real
//  notifications. The default in production is still
//  `UNUserNotificationCenter.current()` — no behaviour change.
//

import Foundation
import UserNotifications
import CatchlightCore
import os

/// Minimal seam around the parts of `UNUserNotificationCenter` that
/// `ReminderScheduler` actually uses. `UNUserNotificationCenter` already
/// conforms via the extension below — production code is unchanged.
public protocol NotificationScheduling: AnyObject {
    func add(_ request: UNNotificationRequest)
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

extension UNUserNotificationCenter: NotificationScheduling {
    public func add(_ request: UNNotificationRequest) {
        // Errors are logged (no content!) rather than silently dropped — an
        // identifier or trigger problem previously left the model holding a
        // reminder the OS would never deliver, with no diagnostic trail.
        self.add(request) { error in
            if let error {
                ReminderScheduler.logger.error("UNUserNotificationCenter.add failed: \(String(describing: error))")
            }
        }
    }
}

public final class ReminderScheduler {

    public static let categoryIdentifier = "TAKE_REMINDER"
    /// `userInfo` key carrying the reminder's ORIGINAL "when" text across snoozes, so a
    /// snoozed re-nudge can read "Snoozed — Originally due …" (owner 2026-06-21).
    static let dueTextKey = "ckDueText"
    /// `userInfo` flag marking a notification as a SNOOZED re-nudge (owner 2026-06-21),
    /// so the app can detect — by inspecting pending requests on foreground — which
    /// reminders are currently snoozed and show "SNOOZED" rather than "OVERDUE" on the
    /// Take edge. Snooze never writes the encrypted store (it runs while locked), so a
    /// pending notification is the only place this state lives.
    static let snoozedFlagKey = "ckSnoozed"
    static let logger = Logger(subsystem: "com.considus.catchlight", category: "reminders")

    /// The time of day an ALL-DAY reminder's alarm fires (model C, owner 2026-06-18).
    /// An all-day "when" has no meaningful time component, so when its alarm is on the
    /// scheduler substitutes this hour rather than firing at the stored (midnight-ish)
    /// time. 9am — a morning nudge for "today"-type items.
    public static let allDayFireHour = 9

    /// How many upcoming occurrences of a repeating reminder are pre-scheduled as
    /// individual alarms (owner 2026-06-21). Each is independently cancellable, so
    /// "delete this occurrence" drops exactly one. The window is re-armed whenever the
    /// app opens, so it stays full as occurrences fire; sized modestly because iOS caps
    /// total pending alarms at 64 across all reminders. 12 ⇒ ~12 days of daily cover
    /// between app opens (weeks/months for the coarser cadences).
    static let recurrenceWindow = 12

    /// Identifier of the `index`-th occurrence in a repeating reminder's window. Namespaced
    /// under the Take's base identifier so the whole window cancels together.
    static func windowIdentifier(base: String, index: Int) -> String { "\(base)#\(index)" }

    /// Every identifier a reminder might own — the one-shot id plus the full recurring
    /// window — so a single cancel clears it whichever kind it is.
    static func allIdentifiers(base: String) -> [String] {
        [base] + (0..<recurrenceWindow).map { windowIdentifier(base: base, index: $0) }
    }

    private let center: NotificationScheduling
    private let now: () -> Date

    public init(center: NotificationScheduling = UNUserNotificationCenter.current(),
                now: @escaping () -> Date = Date.init) {
        self.center = center
        self.now = now
    }

    /// Request permission. Per §8.3, call this when the user adds their FIRST
    /// time-based reminder during onboarding — not at launch.
    /// Goes through the injected seam (previously bypassed it straight to
    /// `UNUserNotificationCenter.current()`, defeating the Task 7.2 seam).
    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Localised "when" line for the notification subtitle — e.g. "Today at 3:00 PM" /
    /// "Tomorrow at 09:00" / "14 Jul 2026 at 3:00 PM", following the user's Region and
    /// 12/24-hour preference (style-based formatter, never a hardcoded pattern). An
    /// all-day reminder shows the DAY only (its time component is meaningless — see the
    /// all-day fire-hour substitution below).
    static func scheduledSubtitle(for reminder: TimeReminder) -> String {
        subtitle(for: reminder.scheduledDate, isAllDay: reminder.isAllDay)
    }

    /// Subtitle for a specific occurrence instant — used per-occurrence when a recurring
    /// reminder is scheduled as a window of individual alarms (owner 2026-06-21).
    static func subtitle(for date: Date, isAllDay: Bool) -> String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true   // "Today"/"Tomorrow" where apt
        formatter.dateStyle = .medium
        formatter.timeStyle = isAllDay ? .none : .short
        return formatter.string(from: date)
    }

    /// Schedule the local notification for a Take's time reminder.
    ///
    /// SEMANTICS (decided 2026-06-10): `TimeReminder.scheduledDate` is an
    /// ABSOLUTE INSTANT and the notification fires at that instant regardless of
    /// where in the world the device is. The trigger pins `timeZone` so the
    /// calendar components are evaluated in the zone they were computed in —
    /// previously no zone was set, so the components floated with the device's
    /// current zone and a travelling user's reminder silently drifted away from
    /// the stored instant.
    ///
    /// Past-dated reminders are refused: a `repeats: false` calendar trigger
    /// whose components are in the past never fires, so scheduling one would
    /// leave the model holding a reminder that silently never delivers. The UI
    /// prevents picking past dates; this is the defence at the boundary.
    public func scheduleReminder(for take: Take) {
        guard let reminder = take.timeReminder else { return }
        // Model C (owner 2026-06-18): a "when" only fires a notification when its alarm
        // is enabled. A silent (planner-only) reminder schedules nothing.
        guard reminder.alarmEnabled else { return }
        // A reminder marked done schedules nothing — so a FUTURE reminder completed
        // before its trigger never fires (owner 2026-06-21). `reconcileNotification`
        // cancels-then-schedules on every save, so this no-op nets to a cancelled
        // notification when the user marks an upcoming reminder done.
        guard !reminder.isDone else { return }

        if reminder.repeats {
            scheduleRecurringWindow(for: take, reminder: reminder)
        } else {
            scheduleOneShot(for: take, reminder: reminder)
        }
    }

    /// Schedule a single (non-repeating) reminder. Past dates are refused: a
    /// `repeats: false` calendar trigger whose components are in the past never fires,
    /// so scheduling one leaves the model holding a reminder the OS silently drops.
    private func scheduleOneShot(for take: Take, reminder: TimeReminder) {
        let fireDate = resolvedFireDate(reminder)
        guard fireDate > now() else {
            Self.logger.warning("Refusing to schedule a past-dated reminder (id \(reminder.notificationIdentifier, privacy: .public))")
            return
        }
        center.add(request(for: take, occurrence: fireDate, isAllDay: reminder.isAllDay,
                           identifier: reminder.notificationIdentifier))
    }

    /// Schedule a REPEATING reminder as a rolling window of individual one-shot alarms,
    /// one per upcoming occurrence (owner 2026-06-21). iOS offers no "repeat but skip
    /// this date" or "repeat starting from X" for calendar alarms, so a series can only
    /// be expressed as discrete occurrences — which is what makes "delete this
    /// occurrence" able to drop exactly one and keep the rest. The window doesn't
    /// auto-extend; `DailiesViewModel.refreshRecurringSchedules()` re-arms it whenever
    /// the app opens. iOS keeps only the 64 soonest pending alarms across the whole app,
    /// so a large fleet of recurring reminders naturally favours the nearest occurrences.
    private func scheduleRecurringWindow(for take: Take, reminder original: TimeReminder) {
        // Anchor an all-day series at the all-day fire hour so every occurrence lands at
        // 9am (not the stored midnight) and the "next occurrence" maths agrees with the
        // actual fire time.
        var reminder = original
        if reminder.isAllDay {
            reminder.scheduledDate = resolvedFireDate(original)
        }
        var occurrence = reminder.effectiveNextDue(now: now())   // first future fire
        for index in 0..<Self.recurrenceWindow {
            let id = Self.windowIdentifier(base: reminder.notificationIdentifier, index: index)
            center.add(request(for: take, occurrence: occurrence, isAllDay: original.isAllDay, identifier: id))
            occurrence = reminder.nextOccurrence(after: occurrence)
        }
    }

    /// Resolve a reminder's fire instant — the stored time, or the all-day fire hour for
    /// a date-only "when" (its stored time component is meaningless).
    private func resolvedFireDate(_ reminder: TimeReminder) -> Date {
        guard reminder.isAllDay else { return reminder.scheduledDate }
        return Calendar.current.date(bySettingHour: Self.allDayFireHour, minute: 0, second: 0,
                                     of: reminder.scheduledDate) ?? reminder.scheduledDate
    }

    /// Build a one-shot notification request for a single occurrence instant. Shared by
    /// the one-shot and per-occurrence (window) paths so their content stays identical.
    private func request(for take: Take, occurrence: Date, isAllDay: Bool, identifier: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        // Content-first (owner 2026-06-18): the TAKE'S TEXT is the title, the scheduled
        // "when" is the subtitle. iOS already shows "CATCHLIGHT" + the delivery time in
        // the banner header, so the old `title = "Catchlight"` just duplicated it. The
        // title is the ONLY place Take content crosses the encrypted boundary.
        content.title = String(take.plainText.prefix(100))
        content.subtitle = Self.subtitle(for: occurrence, isAllDay: isAllDay)
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        // Stamp the original "when" text so a later Snooze can show "Originally due …"
        // (owner 2026-06-21), carried forward unchanged on each re-snooze. Text only.
        content.userInfo[Self.dueTextKey] = content.subtitle
        // Time Sensitive (owner 2026-06-18): an explicit reminder should break through
        // Focus / DND and the Scheduled Summary. Alarm-off reminders never reach here.
        content.interruptionLevel = .timeSensitive

        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: occurrence)
        components.timeZone = TimeZone.current   // pin: absolute-instant semantics
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    public func cancelReminder(for take: Take) {
        guard let reminder = take.timeReminder else { return }
        cancelReminder(identifier: reminder.notificationIdentifier)
    }

    /// Cancel by raw identifier — used when the Take no longer carries its
    /// `timeReminder` (reminder removed via the petal fan, Take deleted) so
    /// `cancelReminder(for:)` has nothing to read the identifier from. The app uses the
    /// Take's UUID string as the identifier. Clears BOTH the one-shot id and the whole
    /// recurring window (`<id>#0…`), so it doesn't matter which kind the Take was.
    public func cancelReminder(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: Self.allIdentifiers(base: identifier))
    }

    /// Reschedule on edit: cancel the prior request and add the current one.
    public func reschedule(for take: Take) {
        cancelReminder(for: take)
        scheduleReminder(for: take)
    }

    /// The Take IDs that currently have a PENDING snoozed re-nudge (owner 2026-06-21) —
    /// used to show "SNOOZED" instead of "OVERDUE" on the Take edge. Reads the OS pending
    /// queue (no encryption key needed, so it works even while locked); a notification is
    /// "snoozed" if it carries `snoozedFlagKey`. Identifiers may be a base UUID or a
    /// recurring-window id (`<uuid>#n`), so the base is taken before the `#`. Uses
    /// `UNUserNotificationCenter.current()` directly — this is an app-runtime query, not
    /// part of the injected scheduling seam.
    public func pendingSnoozedTakeIDs() async -> Set<UUID> {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        var ids = Set<UUID>()
        for request in requests where (request.content.userInfo[Self.snoozedFlagKey] as? Bool) == true {
            let base = request.identifier.split(separator: "#", maxSplits: 1).first.map(String.init) ?? request.identifier
            if let uuid = UUID(uuidString: base) { ids.insert(uuid) }
        }
        return ids
    }

    /// Re-nudge a reminder at a snoozed time (owner 2026-06-20). Notification-level ONLY:
    /// it does NOT touch the encrypted store, so it's safe to call from a notification
    /// action that may run while the phone is locked / the app is backgrounded (no key).
    /// Reuses the Take's UUID `identifier` so the snoozed nudge stays tied to the Take
    /// (an in-app "done"/edit, which cancels by UUID, also clears the snooze) and the
    /// already-decrypted `title` (no re-read across the encrypted boundary).
    ///
    /// `dueText` is the reminder's ORIGINAL "when" text (e.g. "Today at 3:00 PM"), shown
    /// as "Snoozed — Originally due …" and carried forward unchanged so it still reads as
    /// the original due time after repeated snoozes (owner 2026-06-21). The re-nudge's
    /// own delivery time is already in the banner header, so echoing it was redundant.
    public func scheduleSnooze(title: String, identifier: String, fireAt: Date, dueText: String) {
        let interval = fireAt.timeIntervalSince(now())
        guard interval > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = dueText.isEmpty ? "Snoozed" : "Snoozed — Originally due \(dueText)"
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier   // snoozed nudge is snoozable again
        content.interruptionLevel = .timeSensitive
        content.userInfo[Self.dueTextKey] = dueText             // carry the original "when" across re-snoozes
        content.userInfo[Self.snoozedFlagKey] = true           // mark as snoozed so the edge can read "SNOOZED"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }
}
