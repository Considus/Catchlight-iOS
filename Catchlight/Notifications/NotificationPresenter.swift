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

    /// Install as the notification-centre delegate. Idempotent — call once, early in
    /// launch (before a notification could be delivered to a foreground app).
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
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
}
