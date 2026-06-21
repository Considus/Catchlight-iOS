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
    /// How often this "when" repeats (owner 2026-06-21). `.none` is a one-shot reminder
    /// — the v1.0 behaviour and the decode default for payloads written before this
    /// field existed. A repeating reminder fires at each matching occurrence (the OS
    /// repeats the trigger), is never "overdue" (it always has a next fire), and stops
    /// when marked done.
    public enum Recurrence: String, Codable, CaseIterable, Sendable {
        case none, hourly, daily, weekly, monthly, annually

        /// User-facing cadence word for the picker and the card label.
        public var label: String {
            switch self {
            case .none:     return "Never"
            case .hourly:   return "Hourly"
            case .daily:    return "Daily"
            case .weekly:   return "Weekly"
            case .monthly:  return "Monthly"
            case .annually: return "Annually"
            }
        }
    }

    /// The moment the Take is scheduled for (its "when"). For an all-day item the time
    /// component is display-ignored; the scheduler substitutes a default fire time.
    /// For a repeating reminder this is the ANCHOR — the recurrence is derived from its
    /// components (its time-of-day, weekday, day-of-month, etc.).
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

    /// How often the reminder repeats (owner 2026-06-21). `.none` for a one-shot.
    public var recurrence: Recurrence

    /// Whether the reminder repeats — a one-shot when `.none`.
    public var repeats: Bool { recurrence != .none }

    public init(
        scheduledDate: Date,
        isDelivered: Bool = false,
        notificationIdentifier: String,
        alarmEnabled: Bool = true,
        isDone: Bool = false,
        isAllDay: Bool = false,
        recurrence: Recurrence = .none
    ) {
        self.scheduledDate = scheduledDate
        self.isDelivered = isDelivered
        self.notificationIdentifier = notificationIdentifier
        self.alarmEnabled = alarmEnabled
        self.isDone = isDone
        self.isAllDay = isAllDay
        self.recurrence = recurrence
    }

    // Explicit Codable (synthesised offers no decoding defaults): new fields use
    // `decodeIfPresent` so older payloads keep decoding. `alarmEnabled` defaults TRUE
    // (old reminders always notified); `isDone` / `isAllDay` default false.
    enum CodingKeys: String, CodingKey {
        case scheduledDate, isDelivered, notificationIdentifier
        case alarmEnabled, isDone, isAllDay, recurrence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.scheduledDate = try c.decode(Date.self, forKey: .scheduledDate)
        self.isDelivered = try c.decodeIfPresent(Bool.self, forKey: .isDelivered) ?? false
        self.notificationIdentifier = try c.decode(String.self, forKey: .notificationIdentifier)
        self.alarmEnabled = try c.decodeIfPresent(Bool.self, forKey: .alarmEnabled) ?? true
        self.isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        self.isAllDay = try c.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        self.recurrence = try c.decodeIfPresent(Recurrence.self, forKey: .recurrence) ?? .none
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scheduledDate, forKey: .scheduledDate)
        try c.encode(isDelivered, forKey: .isDelivered)
        try c.encode(notificationIdentifier, forKey: .notificationIdentifier)
        try c.encode(alarmEnabled, forKey: .alarmEnabled)
        try c.encode(isDone, forKey: .isDone)
        try c.encode(isAllDay, forKey: .isAllDay)
        try c.encode(recurrence, forKey: .recurrence)
    }
}

// MARK: - Recurrence maths (owner 2026-06-21)

public extension TimeReminder.Recurrence {
    /// The `DateComponents` that DEFINE a match for this cadence, taken from `date` at
    /// the right granularity — the SINGLE source the scheduler's repeating trigger and
    /// `TimeReminder.nextOccurrence` both use, so "fires every X" and "the next X" can
    /// never disagree:
    ///   • none     → full date (a one-shot instant)
    ///   • hourly   → minute            (every hour at :MM)
    ///   • daily    → hour, minute      (every day at HH:MM)
    ///   • weekly   → weekday + time    (every week on that weekday)
    ///   • monthly  → day + time        (every month on that date)
    ///   • annually → month, day + time (every year on that date)
    func matchingComponents(from date: Date, calendar: Calendar = .current) -> DateComponents {
        switch self {
        case .none:     return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        case .hourly:   return calendar.dateComponents([.minute], from: date)
        case .daily:    return calendar.dateComponents([.hour, .minute], from: date)
        case .weekly:   return calendar.dateComponents([.weekday, .hour, .minute], from: date)
        case .monthly:  return calendar.dateComponents([.day, .hour, .minute], from: date)
        case .annually: return calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        }
    }
}

public extension TimeReminder {
    /// The next time this reminder fires strictly after `date`, by its cadence. A
    /// one-shot just returns its scheduled instant. The cadence components are read
    /// from `scheduledDate`, so a "weekly" set on a Tuesday lands on the next Tuesday.
    func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date {
        guard repeats else { return scheduledDate }
        let comps = recurrence.matchingComponents(from: scheduledDate, calendar: calendar)
        return calendar.nextDate(after: date, matching: comps,
                                 matchingPolicy: .nextTimePreservingSmallerComponents) ?? scheduledDate
    }

    /// The upcoming due instant to DISPLAY (owner 2026-06-21): the stored date while it
    /// is still ahead (so a manual "Done"/"skip" that advances it shows immediately),
    /// otherwise the live next occurrence — so a recurring card is never stale even if
    /// the user never acts on it. A one-shot just shows its scheduled instant.
    func effectiveNextDue(now: Date, calendar: Calendar = .current) -> Date {
        guard repeats else { return scheduledDate }
        return scheduledDate > now ? scheduledDate : nextOccurrence(after: now, calendar: calendar)
    }
}
