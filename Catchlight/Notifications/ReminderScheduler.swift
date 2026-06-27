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
    /// Remove ALREADY-DELIVERED notifications still sitting in Notification Centre. Distinct
    /// from `removePendingNotificationRequests`, which only drops not-yet-fired alarms — a
    /// delivered banner survives an edit/delete otherwise (owner 2026-06-27). `UNUserNotificationCenter`
    /// satisfies this natively.
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
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

    /// Global ceiling on pending alarms the app keeps registered at once (owner
    /// 2026-06-21). iOS hard-caps the system at 64 across the WHOLE app and silently
    /// drops the rest, so a fleet of recurring reminders (each wanting a window) could
    /// starve a coarse-cadence series out entirely. `rescheduleAll` plans every alarm,
    /// then keeps only the soonest `maxPendingAlarms`, leaving headroom under 64 for the
    /// snooze/catch-up ids and any single-edit scheduled between rebuilds.
    static let maxPendingAlarms = 60

    /// How long after the app notices a missed all-day fire time it nudges anyway (owner
    /// 2026-06-21). See `scheduleReminder`'s all-day catch-up.
    static let allDayLateLeadSeconds: TimeInterval = 60

    /// Identifier of the `index`-th occurrence in a repeating reminder's window. Namespaced
    /// under the Take's base identifier so the whole window cancels together.
    static func windowIdentifier(base: String, index: Int) -> String { "\(base)#\(index)" }

    /// Identifier for a SNOOZED re-nudge (owner 2026-06-21). A dedicated namespace — NOT a
    /// window slot — so the app-open recurring rebuild (which only clears base+window) can
    /// never clobber a pending snooze, while an explicit edit/delete still clears it.
    static func snoozeIdentifier(base: String) -> String { "\(base)#snooze" }

    /// Identifier for an all-day "catch-up" nudge (owner 2026-06-21) — the same reasoning
    /// as snooze: dedicated namespace so a rebuild neither drops nor repeats it.
    static func catchUpIdentifier(base: String) -> String { "\(base)#today" }

    /// The base one-shot id plus the full recurring window — the scope a periodic REBUILD
    /// clears. Deliberately EXCLUDES the snooze + catch-up ids so those survive a rebuild.
    static func windowAndBaseIdentifiers(base: String) -> [String] {
        [base] + (0..<recurrenceWindow).map { windowIdentifier(base: base, index: $0) }
    }

    /// EVERY identifier a reminder might own — base, window, snooze, and catch-up — so a
    /// single explicit cancel (reminder removed, Take deleted/edited) clears all of them.
    static func allIdentifiers(base: String) -> [String] {
        windowAndBaseIdentifiers(base: base) + [snoozeIdentifier(base: base), catchUpIdentifier(base: base)]
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
    ///
    /// ABSOLUTE, never relative (owner 2026-06-27). A notification's subtitle is baked at
    /// SCHEDULE time and iOS can't re-evaluate it on delivery, so relative wording froze:
    /// a daily occurrence scheduled yesterday-for-today still read "Tomorrow at 09:00"
    /// when it actually fired today — which looked like a stray "notification for the next
    /// instance" stacked next to the real one. An absolute date is correct whenever it is
    /// delivered. (The in-app card still formats relatively — it re-evaluates live.)
    static func subtitle(for date: Date, isAllDay: Bool) -> String {
        let formatter = DateFormatter()
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
        // Model C (owner 2026-06-18): a "when" only fires a notification when its alarm is
        // enabled; a silent (planner-only) reminder schedules nothing. A reminder marked
        // done also schedules nothing (a future reminder completed early never fires).
        guard reminder.alarmEnabled, !reminder.isDone else { return }

        let alarms = plannedAlarms(for: take, now: now())
        if !alarms.isEmpty {
            alarms.forEach { center.add($0.request) }
            return
        }

        // No future occurrence to schedule. R5 (owner 2026-06-21): an ALL-DAY reminder set
        // for TODAY whose default 9am fire time has already passed still deserves its nudge
        // — previously it was silently dropped. Fire promptly under a dedicated catch-up id
        // so a later app-open rebuild (which clears only base+window) neither drops nor
        // repeats it.
        if !reminder.repeats, reminder.isAllDay,
           Calendar.current.isDate(reminder.scheduledDate, inSameDayAs: now()) {
            center.add(catchUpRequest(for: take, reminder: reminder))
            return
        }
        // Genuinely past one-shot: a calendar trigger in the past never fires, so refuse it
        // rather than leave the model holding a reminder the OS silently drops.
        Self.logger.warning("Refusing to schedule a past-dated reminder (id \(reminder.notificationIdentifier, privacy: .public))")
    }

    /// Rebuild the ENTIRE pending-alarm set from the authoritative Take list, capped at the
    /// global iOS budget and favouring the soonest occurrences (owner 2026-06-21). Called on
    /// every app open via `DailiesViewModel`. Clears each reminder's base+window (so stale
    /// occurrences drop and recurring windows re-arm) but deliberately NOT its snooze /
    /// catch-up ids, so a pending snooze survives the rebuild. Then plans every alarm across
    /// all reminders, keeps only the soonest `maxPendingAlarms`, and registers them — so a
    /// large fleet can never silently overflow iOS's 64-pending cap.
    public func rescheduleAll(takes: [Take]) {
        let n = now()
        let toClear = takes
            .compactMap { $0.timeReminder?.notificationIdentifier }
            .flatMap { Self.windowAndBaseIdentifiers(base: $0) }
        if !toClear.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: toClear)
        }
        let chosen = takes
            .flatMap { plannedAlarms(for: $0, now: n) }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(Self.maxPendingAlarms)
        chosen.forEach { center.add($0.request) }
    }

    /// A planned alarm + the instant it fires, so the global rebuild can sort by soonest.
    private struct PlannedAlarm {
        let request: UNNotificationRequest
        let fireDate: Date
    }

    /// The set of alarms a Take's reminder wants right now — empty for a silent/done
    /// reminder or a genuinely-past one-shot, one for a future one-shot, or the rolling
    /// window for a repeating reminder. Single-sourced so the per-save and global-rebuild
    /// paths schedule identical content. (The all-day "today" catch-up is intentionally NOT
    /// here — it is a single-save-only extra; see `scheduleReminder`.)
    private func plannedAlarms(for take: Take, now: Date) -> [PlannedAlarm] {
        guard let reminder = take.timeReminder, reminder.alarmEnabled, !reminder.isDone else { return [] }

        if reminder.repeats {
            // Anchor an all-day series at the all-day fire hour so every occurrence lands at
            // 9am (not the stored midnight) and the "next occurrence" maths agrees with the
            // fire time. iOS offers no "repeat but skip this date", so a series is expressed
            // as discrete occurrences — which is what lets "delete this occurrence" drop one.
            var r = reminder
            if r.isAllDay { r.scheduledDate = resolvedFireDate(reminder) }
            var occurrence = r.effectiveNextDue(now: now)
            var out: [PlannedAlarm] = []
            for index in 0..<Self.recurrenceWindow {
                let id = Self.windowIdentifier(base: reminder.notificationIdentifier, index: index)
                out.append(PlannedAlarm(
                    request: calendarRequest(for: take, occurrence: occurrence,
                                             isAllDay: reminder.isAllDay, identifier: id),
                    fireDate: occurrence))
                occurrence = r.nextOccurrence(after: occurrence)
            }
            return out
        }

        let fireDate = resolvedFireDate(reminder)
        guard fireDate > now else { return [] }
        return [PlannedAlarm(
            request: calendarRequest(for: take, occurrence: fireDate,
                                     isAllDay: reminder.isAllDay,
                                     identifier: reminder.notificationIdentifier),
            fireDate: fireDate)]
    }

    /// Resolve a reminder's fire instant — the stored time, or the all-day fire hour for
    /// a date-only "when" (its stored time component is meaningless).
    private func resolvedFireDate(_ reminder: TimeReminder) -> Date {
        guard reminder.isAllDay else { return reminder.scheduledDate }
        return Calendar.current.date(bySettingHour: Self.allDayFireHour, minute: 0, second: 0,
                                     of: reminder.scheduledDate) ?? reminder.scheduledDate
    }

    /// Shared notification content for a single occurrence — the TAKE'S TEXT as title, the
    /// "when" as subtitle (the title is the ONLY place Take content crosses the encrypted
    /// boundary). Time-Sensitive so an explicit reminder breaks through Focus / DND.
    private func makeContent(for take: Take, occurrence: Date, isAllDay: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(take.plainText.prefix(100))
        content.subtitle = Self.subtitle(for: occurrence, isAllDay: isAllDay)
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        // Group every notification for THIS reminder (all recurring-window occurrences,
        // its snooze, its catch-up) under one thread keyed on the Take, so iOS STACKS
        // them in Notification Centre instead of showing each delivered occurrence as a
        // separate banner that reads as a duplicate (owner 2026-06-27). The Take id is
        // opaque — no content crosses the boundary here.
        content.threadIdentifier = take.id.uuidString
        // Stamp the original "when" text so a later Snooze can show "Originally due …".
        content.userInfo[Self.dueTextKey] = content.subtitle
        content.interruptionLevel = .timeSensitive
        return content
    }

    /// Build a calendar-triggered request for a single occurrence instant.
    private func calendarRequest(for take: Take, occurrence: Date, isAllDay: Bool, identifier: String) -> UNNotificationRequest {
        let content = makeContent(for: take, occurrence: occurrence, isAllDay: isAllDay)
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: occurrence)
        components.timeZone = TimeZone.current   // pin: absolute-instant semantics
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    /// Build the all-day "catch-up" request (R5): a short interval trigger so a same-day
    /// all-day reminder whose 9am slot has passed still nudges today. The subtitle shows the
    /// day (its time is meaningless); the dedicated `#today` id keeps a rebuild from
    /// dropping or repeating it.
    private func catchUpRequest(for take: Take, reminder: TimeReminder) -> UNNotificationRequest {
        let content = makeContent(for: take, occurrence: reminder.scheduledDate, isAllDay: true)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Self.allDayLateLeadSeconds, repeats: false)
        return UNNotificationRequest(identifier: Self.catchUpIdentifier(base: reminder.notificationIdentifier),
                                     content: content, trigger: trigger)
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
        let ids = Self.allIdentifiers(base: identifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        // ALSO drop any already-delivered banner for this reminder (owner 2026-06-27). On an
        // edit/delete the old notification's title/time is now stale — e.g. a renamed reminder
        // left its previous-name banner stuck in Notification Centre, which then sat alongside
        // the new one and read as a duplicate. This is the EXPLICIT-cancel path only (edit,
        // delete, remove-reminder); the app-open `rescheduleAll` rebuild deliberately clears
        // only PENDING, so a legitimately-fired reminder the user hasn't acted on is preserved.
        center.removeDeliveredNotifications(withIdentifiers: ids)
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
        // Same thread as the reminder's other notifications so the snooze stacks with
        // them (the id is `<uuid>#snooze`; take the base before the `#`).
        content.threadIdentifier = identifier.split(separator: "#", maxSplits: 1).first.map(String.init) ?? identifier
        content.interruptionLevel = .timeSensitive
        content.userInfo[Self.dueTextKey] = dueText             // carry the original "when" across re-snoozes
        content.userInfo[Self.snoozedFlagKey] = true           // mark as snoozed so the edge can read "SNOOZED"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }
}
