//
//  NotificationPresenter.swift
//  Catchlight (iOS app target)
//
//  Foreground presentation for Take reminders.
//
//  iOS suppresses a local notification's banner/sound while the app is in the
//  FOREGROUND unless a `UNUserNotificationCenterDelegate` returns presentation
//  options from `willPresent`. Catchlight shipped without that delegate, so a
//  reminder whose time arrived while the user had the app open fired SILENTLY —
//  nothing showed, and the Take simply flipped to "overdue" (owner-reported
//  2026-06-18). This restores the banner + sound in the foreground.
//
//  Backgrounded / locked delivery is unaffected — the system presents those
//  regardless of any delegate; this only governs the frontmost case.
//
//  Retained for the PROCESS lifetime via `shared`: a SwiftUI `App` is a value type
//  the framework may re-create, and `UNUserNotificationCenter.delegate` is a weak
//  reference, so the delegate must not live on the App struct or it would be
//  deallocated and the behaviour would silently regress.
//

import UserNotifications

final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationPresenter()

    /// The single "Snooze" pull-down action on a reminder banner (owner 2026-06-20). A
    /// BACKGROUND action (no `.foreground`) so snoozing never opens the app or demands
    /// Face ID — it just re-nudges the notification by the user's default duration
    /// (`SettingsViewModel.SnoozeDuration`, a plain preference readable while locked).
    private static let snoozeActionIdentifier = "SNOOZE"

    /// The "Dismiss" pull-down action on a reminder banner (owner 2026-06-22). Stops the
    /// reminder nagging WITHOUT deleting it: it turns the alarm off (`alarmEnabled = false`)
    /// so the Take keeps its date on the timeline but never fires again. Like Snooze it's a
    /// BACKGROUND action (no `.foreground`) — it cancels the pending OS alarms immediately
    /// (works while locked) and queues the store change for the next unlock (see
    /// `PendingReminderActions`), so it never opens the app or demands Face ID.
    private static let dismissActionIdentifier = "DISMISS"

    /// Install as the notification-centre delegate AND register the reminder category.
    /// Idempotent — call once, early in launch (before a notification could be delivered
    /// to a foreground app).
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
        registerReminderCategory()
    }

    /// (Re)register the reminder category's Snooze action. Called at launch and again
    /// whenever the snooze-duration setting changes (from Settings), so the button label
    /// ("Snooze for 1 hour") stays in sync with `SettingsViewModel.SnoozeDuration`. The
    /// action TITLE is fixed at registration, hence the refresh; the snooze BEHAVIOUR
    /// reads the duration live at tap time regardless (see `didReceive`).
    ///
    /// `zzz` SF Symbol on the action (iOS 15+) — the ONLY visual control Apple exposes
    /// for a notification action; its position + the button's shape/colour/font are
    /// system-styled and can't be changed (owner 2026-06-20).
    static func registerReminderCategory() {
        let snooze = UNNotificationAction(
            identifier: snoozeActionIdentifier,
            title: "Snooze for \(SettingsViewModel.SnoozeDuration.current.label)",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "zzz"))
        // "Dismiss" — bell.slash reads as "stop reminding me". A plain (non-destructive)
        // background action: it silences the reminder but keeps the Take, so it isn't a
        // delete. Placed after Snooze, the existing primary action.
        let dismiss = UNNotificationAction(
            identifier: dismissActionIdentifier,
            title: "Dismiss",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "bell.slash"))
        let category = UNNotificationCategory(
            identifier: ReminderScheduler.categoryIdentifier,
            actions: [snooze, dismiss],
            intentIdentifiers: [],
            options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Present reminders in the foreground too: banner + sound, and list them in
    /// Notification Centre. Without returning these, a frontmost app shows nothing.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Handle a tapped notification action. A snooze re-nudges the SAME reminder (its
    /// UUID identifier) at the chosen time, reusing the banner's already-decrypted title.
    /// It deliberately does NOT rewrite the Take's stored reminder time — that needs the
    /// encryption key, which is unavailable while the phone is locked / the app is
    /// backgrounded (where snooze runs). Snooze is a notification-level re-nudge.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let request = response.notification.request
        // The reminder's base id (a recurring occurrence fires as `<uuid>#n`; strip the `#n`).
        let base = request.identifier.split(separator: "#", maxSplits: 1).first.map(String.init) ?? request.identifier

        switch response.actionIdentifier {
        case Self.snoozeActionIdentifier:
            handleSnooze(request: request, base: base)
        case Self.dismissActionIdentifier:
            handleDismiss(request: request, base: base)
        default:
            return
        }
    }

    /// "Dismiss": stop the CURRENT instance nagging — without affecting a recurring series'
    /// future occurrences (owner 2026-06-22). Cancels ONLY the fired instance plus any snooze
    /// / all-day catch-up for this reminder (works while locked — it's the OS queue, no key);
    /// the recurring window ids `<uuid>#0…#11` are deliberately left intact, so a daily/weekly
    /// reminder keeps firing. It then queues the dismiss for the next unlock: the drain
    /// (`DailiesViewModel.applyPendingReminderActions`) turns the alarm off in the store ONLY
    /// when the reminder is a ONE-SHOT; a recurring reminder gets no store change at all.
    private func handleDismiss(request: UNNotificationRequest, base: String) {
        // Also clear the follow-up chain (owner 2026-06-28): dismissing means "I've handled
        // it / stop", so the auto re-nudges must not keep firing.
        let ids = [request.identifier,
                   ReminderScheduler.snoozeIdentifier(base: base),
                   ReminderScheduler.catchUpIdentifier(base: base)]
            + ReminderScheduler.followUpIdentifiers(base: base)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        PendingReminderActions.enqueueDismiss(takeID: base)
    }

    /// Snooze (background, works while locked): re-nudge the SAME reminder later without
    /// touching the encrypted store.
    private func handleSnooze(request: UNNotificationRequest, base: String) {
        let fireAt = Date().addingTimeInterval(SettingsViewModel.SnoozeDuration.current.seconds)
        // The ORIGINAL "when" text, stamped at first schedule and carried across snoozes,
        // so the re-nudge reads "Originally due …" rather than the (redundant) re-fire
        // time. Fall back to the current subtitle for notifications scheduled before this
        // existed (only true for ones already pending at upgrade).
        let dueText = (request.content.userInfo[ReminderScheduler.dueTextKey] as? String)
            ?? request.content.subtitle
        // Snoozing replaces the automatic follow-up chain with the user's chosen re-nudge —
        // clear the pending follow-ups so they don't double up (owner 2026-06-28).
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ReminderScheduler.followUpIdentifiers(base: base))
        // Re-nudge under the reminder's DEDICATED snooze id, not the fired request's own id
        // (owner 2026-06-21). A recurring occurrence fires as `<uuid>#n`; reusing that id let
        // the next app-open window rebuild overwrite the snooze. The `base` (the `#n` already
        // stripped) snoozes under `<uuid>#snooze`, a namespace the rebuild leaves untouched —
        // so the snooze survives, and an in-app edit/delete (which cancels every id including
        // `#snooze`) still clears it.
        ReminderScheduler().scheduleSnooze(
            title: request.content.title,
            identifier: ReminderScheduler.snoozeIdentifier(base: base),
            fireAt: fireAt,
            dueText: dueText)
    }
}
