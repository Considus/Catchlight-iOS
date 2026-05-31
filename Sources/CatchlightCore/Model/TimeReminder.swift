//
//  TimeReminder.swift
//  CatchlightCore
//
//  Time-based reminder payload (Phase 5 brief §4.3). Location-based reminders are
//  a separate type (LocationTrigger) and are out of scope for v1.0.
//

import Foundation

public struct TimeReminder: Codable, Equatable, Sendable {
    public var scheduledDate: Date
    public var isDelivered: Bool

    /// Matches the `UNNotificationRequest` identifier so the scheduled local
    /// notification can be cancelled or rescheduled (see ReminderScheduler in the
    /// iOS target). Stored as a stable string, typically the Take UUID.
    public var notificationIdentifier: String

    public init(scheduledDate: Date, isDelivered: Bool = false, notificationIdentifier: String) {
        self.scheduledDate = scheduledDate
        self.isDelivered = isDelivered
        self.notificationIdentifier = notificationIdentifier
    }
}
