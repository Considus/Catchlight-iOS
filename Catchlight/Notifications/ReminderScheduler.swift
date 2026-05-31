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

import Foundation
import UserNotifications
import CatchlightCore

public final class ReminderScheduler {

    public static let categoryIdentifier = "TAKE_REMINDER"

    public init() {}

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
        UNUserNotificationCenter.current().add(request)
    }

    public func cancelReminder(for take: Take) {
        guard let reminder = take.timeReminder else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminder.notificationIdentifier])
    }

    /// Reschedule on edit: cancel the prior request and add the current one.
    public func reschedule(for take: Take) {
        cancelReminder(for: take)
        scheduleReminder(for: take)
    }
}
