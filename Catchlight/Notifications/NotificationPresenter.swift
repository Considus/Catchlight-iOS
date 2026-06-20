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

    /// Snooze actions shown when the user pulls down / long-presses a reminder banner
    /// (owner 2026-06-20). Background actions (no `.foreground`) so snoozing never opens
    /// the app or demands Face ID — it just re-nudges the notification.
    private enum Snooze {
        static let fifteenMinutes = "SNOOZE_15M"
        static let oneHour = "SNOOZE_1H"
        static let tomorrow = "SNOOZE_TOMORROW"
    }

    /// Install as the notification-centre delegate AND register the reminder category's
    /// snooze actions. Idempotent — call once, early in launch (before a notification
    /// could be delivered to a foreground app).
    static func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = shared
        let actions = [
            UNNotificationAction(identifier: Snooze.fifteenMinutes, title: "Snooze 15 minutes", options: []),
            UNNotificationAction(identifier: Snooze.oneHour, title: "Snooze 1 hour", options: []),
            UNNotificationAction(identifier: Snooze.tomorrow, title: "Tomorrow morning", options: []),
        ]
        let category = UNNotificationCategory(
            identifier: ReminderScheduler.categoryIdentifier,
            actions: actions,
            intentIdentifiers: [],
            options: [])
        center.setNotificationCategories([category])
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
        guard let fireAt = Self.snoozeDate(for: response.actionIdentifier) else { return }
        let request = response.notification.request
        ReminderScheduler().scheduleSnooze(
            title: request.content.title,
            identifier: request.identifier,
            fireAt: fireAt)
    }

    /// The target instant for a snooze action, or nil for any non-snooze action
    /// (e.g. the default tap, which just opens the app).
    private static func snoozeDate(for actionIdentifier: String, now: Date = Date()) -> Date? {
        switch actionIdentifier {
        case Snooze.fifteenMinutes: return now.addingTimeInterval(15 * 60)
        case Snooze.oneHour:        return now.addingTimeInterval(60 * 60)
        case Snooze.tomorrow:
            let cal = Calendar.current
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
            return cal.date(bySettingHour: ReminderScheduler.allDayFireHour,
                            minute: 0, second: 0, of: tomorrow)
        default:
            return nil
        }
    }
}
