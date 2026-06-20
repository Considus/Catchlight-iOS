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
    static let logger = Logger(subsystem: "com.considus.catchlight", category: "reminders")

    /// The time of day an ALL-DAY reminder's alarm fires (model C, owner 2026-06-18).
    /// An all-day "when" has no meaningful time component, so when its alarm is on the
    /// scheduler substitutes this hour rather than firing at the stored (midnight-ish)
    /// time. 9am — a morning nudge for "today"-type items.
    public static let allDayFireHour = 9

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
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true   // "Today"/"Tomorrow" where apt
        formatter.dateStyle = .medium
        formatter.timeStyle = reminder.isAllDay ? .none : .short
        return formatter.string(from: reminder.scheduledDate)
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

        // An all-day "when" has no meaningful time component — fire at the default
        // hour instead of the stored (effectively-midnight) time (model C). The
        // past-date guard and the trigger both use this resolved instant.
        let fireDate: Date = {
            guard reminder.isAllDay else { return reminder.scheduledDate }
            return Calendar.current.date(bySettingHour: Self.allDayFireHour,
                                         minute: 0, second: 0,
                                         of: reminder.scheduledDate) ?? reminder.scheduledDate
        }()

        guard fireDate > now() else {
            Self.logger.warning("Refusing to schedule a past-dated reminder (id \(reminder.notificationIdentifier, privacy: .public))")
            return
        }

        let content = UNMutableNotificationContent()
        // Content-first (owner 2026-06-18): the TAKE'S TEXT is the title, the scheduled
        // "when" is the subtitle. iOS already shows "CATCHLIGHT" + the delivery time in
        // the banner header, so the old `title = "Catchlight"` just duplicated it. The
        // title is now the ONLY place Take content crosses the encrypted boundary (was
        // the body) — same accepted, user-chosen lock-screen exposure, different field.
        content.title = String(take.plainText.prefix(100))
        content.subtitle = Self.scheduledSubtitle(for: reminder)
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        // Time Sensitive (owner 2026-06-18): a reminder the user explicitly set should
        // break through Focus / Do Not Disturb and the Scheduled Summary, like Apple's
        // Reminders. Requires the matching entitlement (see project.yml). If the alarm
        // is off we never get here (guarded above), so only real alarms are elevated.
        content.interruptionLevel = .timeSensitive

        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        components.timeZone = TimeZone.current   // pin: absolute-instant semantics
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: reminder.notificationIdentifier,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    public func cancelReminder(for take: Take) {
        guard let reminder = take.timeReminder else { return }
        center.removePendingNotificationRequests(withIdentifiers: [reminder.notificationIdentifier])
    }

    /// Cancel by raw identifier — used when the Take no longer carries its
    /// `timeReminder` (reminder removed via the petal fan, Take deleted) so
    /// `cancelReminder(for:)` has nothing to read the identifier from. The app
    /// uses the Take's UUID string as the notification identifier.
    public func cancelReminder(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Reschedule on edit: cancel the prior request and add the current one.
    public func reschedule(for take: Take) {
        cancelReminder(for: take)
        scheduleReminder(for: take)
    }

    /// Re-nudge a reminder at a snoozed time (owner 2026-06-20). Notification-level ONLY:
    /// it does NOT touch the encrypted store, so it's safe to call from a notification
    /// action that may run while the phone is locked / the app is backgrounded (no key).
    /// Reuses the Take's UUID `identifier` so the snoozed nudge stays tied to the Take
    /// (an in-app "done"/edit, which cancels by UUID, also clears the snooze) and the
    /// already-decrypted `title` (no re-read across the encrypted boundary).
    public func scheduleSnooze(title: String, identifier: String, fireAt: Date) {
        let interval = fireAt.timeIntervalSince(now())
        guard interval > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = "Snoozed — \(Self.snoozeSubtitle(for: fireAt))"
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier   // snoozed nudge is snoozable again
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    /// "Today at 3:15 PM" / "Tomorrow at 09:00" for the snoozed-until subtitle, honouring
    /// the user's Region + 12/24-hour preference (style-based, never a hardcoded pattern).
    static func snoozeSubtitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
