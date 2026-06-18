//
//  TimeReminder.swift
//  CatchlightCore
//
//  A Take's TIME — its "when" (Phase 5 brief §4.3; model "C", owner 2026-06-18).
//  Originally this WAS "the alarm"; it now means the scheduled date the Take is FOR,
//  with the notification as a SELECTABLE property (`alarmEnabled`). A dated-but-silent
//  Take (planner placement, no nag) is just one with `alarmEnabled == false`.
//  Location-based triggers are a separate type (LocationTrigger), a future cluster.
//

import Foundation

public struct TimeReminder: Codable, Equatable, Sendable {
    /// The moment the Take is scheduled for (its "when"). For an all-day item the time
    /// component is display-ignored; the scheduler substitutes a default fire time.
    public var scheduledDate: Date
    public var isDelivered: Bool

    /// Matches the `UNNotificationRequest` identifier so the scheduled local
    /// notification can be cancelled or rescheduled (see ReminderScheduler in the
    /// iOS target). Stored as a stable string, typically the Take UUID.
    public var notificationIdentifier: String

    /// Whether this "when" ALSO fires a local notification (model C, owner 2026-06-18).
    /// `true` = alarm; `false` = silent planner/agenda placement. Defaults true, and
    /// old payloads (written before this field) decode as true, so existing reminders
    /// keep notifying — no behaviour change on migration.
    public var alarmEnabled: Bool

    /// The user marked this scheduled item DONE (owner 2026-06-18). Distinct from
    /// `isDelivered` (whether the notification has fired): a reminder can be Done
    /// before or without ever firing. Drives the "done" filter + the grey card border.
    public var isDone: Bool

    /// Date-only ("for Tuesday", no specific time) vs a timed "when" (owner 2026-06-18).
    /// When true, displays as a day and — if `alarmEnabled` — the scheduler fires at a
    /// default time of day rather than the (meaningless) stored time component.
    public var isAllDay: Bool

    public init(
        scheduledDate: Date,
        isDelivered: Bool = false,
        notificationIdentifier: String,
        alarmEnabled: Bool = true,
        isDone: Bool = false,
        isAllDay: Bool = false
    ) {
        self.scheduledDate = scheduledDate
        self.isDelivered = isDelivered
        self.notificationIdentifier = notificationIdentifier
        self.alarmEnabled = alarmEnabled
        self.isDone = isDone
        self.isAllDay = isAllDay
    }

    // Explicit Codable (synthesised offers no decoding defaults): new fields use
    // `decodeIfPresent` so older payloads keep decoding. `alarmEnabled` defaults TRUE
    // (old reminders always notified); `isDone` / `isAllDay` default false.
    enum CodingKeys: String, CodingKey {
        case scheduledDate, isDelivered, notificationIdentifier
        case alarmEnabled, isDone, isAllDay
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.scheduledDate = try c.decode(Date.self, forKey: .scheduledDate)
        self.isDelivered = try c.decodeIfPresent(Bool.self, forKey: .isDelivered) ?? false
        self.notificationIdentifier = try c.decode(String.self, forKey: .notificationIdentifier)
        self.alarmEnabled = try c.decodeIfPresent(Bool.self, forKey: .alarmEnabled) ?? true
        self.isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        self.isAllDay = try c.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scheduledDate, forKey: .scheduledDate)
        try c.encode(isDelivered, forKey: .isDelivered)
        try c.encode(notificationIdentifier, forKey: .notificationIdentifier)
        try c.encode(alarmEnabled, forKey: .alarmEnabled)
        try c.encode(isDone, forKey: .isDone)
        try c.encode(isAllDay, forKey: .isAllDay)
    }
}
