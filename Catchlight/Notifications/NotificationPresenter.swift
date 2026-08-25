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

    /// "Stop reminding" — ends a REPEATING reminder for good (owner 2026-08-11).
    ///
    /// The gap it fills: "Dismiss" is deliberately this-occurrence-only on a repeating series
    /// (owner 2026-06-22), and "Mark Done" ADVANCES a repeating reminder rather than settling it,
    /// so there was no way at all to stop a series from the notification. Ticking every task
    /// didn't help either, because the reminder is not the checklist.
    ///
    /// Offered ONLY on the repeating category, where it is unambiguous. A BACKGROUND action like
    /// its siblings: it cancels every pending id immediately (the OS queue needs no key, so this
    /// works while locked) and queues the `alarmEnabled = false` store write for the next unlock.
    private static let stopRemindingActionIdentifier = "STOP_REMINDING"

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
        // A REPEATING reminder gets a third action. Last in the list because it is the most
        // final of the three, and `.destructive` so the system styles it as the one that ends
        // something — it stops the series without deleting the Take or its date.
        let stopReminding = UNNotificationAction(
            identifier: stopRemindingActionIdentifier,
            title: "Stop reminding",
            options: [.destructive],
            icon: UNNotificationActionIcon(systemImageName: "bell.slash.fill"))
        let repeatingCategory = UNNotificationCategory(
            identifier: ReminderScheduler.repeatingCategoryIdentifier,
            actions: [snooze, dismiss, stopReminding],
            intentIdentifiers: [],
            options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category, repeatingCategory])
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
        case Self.stopRemindingActionIdentifier:
            handleStopReminding(base: base)
        case UNNotificationDefaultActionIdentifier:
            handleTap(base: base)
        default:
            return
        }
    }

    /// The Take a notification TAP asked to see, waiting for the app to reveal it.
    ///
    /// Owner-reported 2026-08-11: tapping a reminder opened the app on the plain timeline with
    /// no sign of which Take the nudge was about — "I couldn't remember which one to look at",
    /// which defeats the point of the nudge. The default action fell through this delegate's
    /// `default: return` and did nothing at all.
    ///
    /// Held statically as well as broadcast because the two arrival orders differ: on a WARM tap
    /// the app is already listening and the notification below is enough, but on a COLD launch
    /// this delegate can run before any view is observing, so the app drains this on activation
    /// and again after unlock instead.
    private(set) static var pendingRevealTakeID: UUID?

    /// Broadcast so a foregrounded app can reveal immediately rather than waiting for the next
    /// activation.
    static let revealRequested = Notification.Name("catchlight.revealRequested")

    /// Consume the pending reveal, if any.
    static func takePendingReveal() -> UUID? {
        defer { pendingRevealTakeID = nil }
        return pendingRevealTakeID
    }

    /// Tapping the banner itself (as opposed to a pull-down action) — show me that Take.
    ///
    /// `base` has already had any `#` suffix stripped, so this works identically for a plain
    /// reminder, a recurring occurrence (`#n`), a snooze, an all-day catch-up, a follow-up and a
    /// geofence: every one of them is the same Take.
    private func handleTap(base: String) {
        guard let uuid = UUID(uuidString: base) else { return }
        Self.pendingRevealTakeID = uuid
        NotificationCenter.default.post(name: Self.revealRequested, object: nil)
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
        // Record WHICH notification was dismissed (2026-07-01): the geofence fires
        // as `<uuid>#loc`, and a Take can carry both a "when" and a "where" — the
        // drain must silence only the dismissed one.
        let isLocation = request.identifier == ReminderScheduler.locationIdentifier(base: base)
        PendingReminderActions.enqueueDismiss(takeID: base, isLocation: isLocation)
    }

    /// "Stop reminding": end the whole series (owner 2026-08-11).
    ///
    /// Unlike Dismiss, this clears EVERY id the reminder owns — the base, the full recurring
    /// window, the snooze, the all-day catch-up and the follow-up chain — so nothing already
    /// scheduled can fire again. That alone is not enough, though: the app-open rebuild replans
    /// alarms from the store, so without the queued store write the series would simply come
    /// back on next launch. Hence the pending action, drained at unlock when the key exists.
    ///
    /// The Take and its date are untouched, exactly like Dismiss. This silences, it never deletes.
    private func handleStopReminding(base: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ReminderScheduler.allIdentifiers(base: base))
        PendingReminderActions.enqueueStopReminding(takeID: base)
    }

    /// Snooze (background, works while locked): re-nudge the SAME reminder later without
    /// touching the encrypted store.
    private func handleSnooze(request: UNNotificationRequest, base: String) {
        let fireAt = Date().addingTimeInterval(SettingsViewModel.SnoozeDuration.current.seconds)
        // The ORIGINAL "when" text, stamped at first schedule and carried across snoozes,
        // so the re-nudge reads "Originally due …" rather than the (redundant) re-fire
        // time. S1 (audit 2026-08): ONLY a stamped value may be templated — the old
        // subtitle fallback pushed a geofence's "When you arrive at ⟨place⟩" (which
        // stamps no due text, having no due date) through the "Originally due ⟨date⟩"
        // template. Unstamped notifications now read plain "Snoozed", which is true.
        let dueText = (request.content.userInfo[ReminderScheduler.dueTextKey] as? String) ?? ""
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
            dueText: dueText,
            // Carry the FIRED notification's category across, so snoozing a repeating reminder
            // does not quietly drop its "Stop reminding" action from the re-nudge. There is no
            // Take here to re-derive it from (snooze never touches the store).
            categoryIdentifier: request.content.categoryIdentifier)
    }
}
