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

/// Minimal seam around the parts of `UNUserNotificationCenter` that
/// `ReminderScheduler` actually uses. `UNUserNotificationCenter` already
/// conforms via the extension below — production code is unchanged.
public protocol NotificationScheduling: AnyObject {
    func add(_ request: UNNotificationRequest)
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: NotificationScheduling {
    public func add(_ request: UNNotificationRequest) {
        // Wrap the completion-handler form (no `try` available on the variant
        // without a handler in older SDKs). Errors are surfaced through the
        // completion the same way the previous `add(request)` no-handler call
        // did — silently dropped, matching pre-7.2 behaviour.
        self.add(request, withCompletionHandler: nil)
    }
}

public final class ReminderScheduler {

    public static let categoryIdentifier = "TAKE_REMINDER"

    private let center: NotificationScheduling

    public init(center: NotificationScheduling = UNUserNotificationCenter.current()) {
        self.center = center
    }

    /// Request permission. Per §8.3, call this when the user adds their FIRST
    /// time-based reminder during onboarding — not at launch.
    public func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public func scheduleReminder(for take: Take) {
        guard let reminder = take.timeReminder else { return }

        let content = UNMutableNotificationContent()
        content.title = "Catchlight"
        content.body = String(take.bodyText.prefix(100))
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.scheduledDate
        )
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

    /// Reschedule on edit: cancel the prior request and add the current one.
    public func reschedule(for take: Take) {
        cancelReminder(for: take)
        scheduleReminder(for: take)
    }
}
