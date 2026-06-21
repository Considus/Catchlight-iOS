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
        let category = UNNotificationCategory(
            identifier: ReminderScheduler.categoryIdentifier,
            actions: [snooze],
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
        guard response.actionIdentifier == Self.snoozeActionIdentifier else { return }
        let fireAt = Date().addingTimeInterval(SettingsViewModel.SnoozeDuration.current.seconds)
        let request = response.notification.request
        // The ORIGINAL "when" text, stamped at first schedule and carried across snoozes,
        // so the re-nudge reads "Originally due …" rather than the (redundant) re-fire
        // time. Fall back to the current subtitle for notifications scheduled before this
        // existed (only true for ones already pending at upgrade).
        let dueText = (request.content.userInfo[ReminderScheduler.dueTextKey] as? String)
            ?? request.content.subtitle
        ReminderScheduler().scheduleSnooze(
            title: request.content.title,
            identifier: request.identifier,
            fireAt: fireAt,
            dueText: dueText)
    }
}
