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
        guard reminder.scheduledDate > now() else {
            Self.logger.warning("Refusing to schedule a past-dated reminder (id \(reminder.notificationIdentifier, privacy: .public))")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Catchlight"
        content.body = String(take.plainText.prefix(100))
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier

        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.scheduledDate
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
}
