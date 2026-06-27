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
    ///
    /// Normalised to milliseconds — the wire format's resolution (`ISO8601`, `…SSS'Z'`).
    /// Without this a sub-millisecond `scheduledDate` (e.g. the default reminder time is
    /// `Date() + N hours`, which carries full precision) compares UNEQUAL to its own
    /// serialised-and-reloaded copy, so sync's `ConflictResolver` saw "remote differs"
    /// while `modifiedAt` was unchanged and surfaced a PHANTOM CONFLICT — even on one
    /// device (owner-reported 2026-06-27). `createdAt`/`modifiedAt` are normalised for
    /// exactly this reason; this matches them.
    public var scheduledDate: Date {
        didSet { scheduledDate = ISO8601.truncateToMilliseconds(scheduledDate) }
    }
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
        // `didSet` does not fire from an initialiser, so normalise here too.
        self.scheduledDate = ISO8601.truncateToMilliseconds(scheduledDate)
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
        // Normalise on decode so a Take reloaded from disk/cloud equals its in-memory
        // original (the `didSet` does not fire during `init`). This is what makes a
        // no-op sync resolve to `.noChange` instead of a phantom conflict.
        self.scheduledDate = ISO8601.truncateToMilliseconds(try c.decode(Date.self, forKey: .scheduledDate))
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
    ///
    /// Month-end safety (owner 2026-06-21): a `monthly` reminder anchored on the 29th–
    /// 31st, or an `annually` one on 29 Feb, would otherwise be SKIPPED by
    /// `Calendar.nextDate` in any month/year lacking that day — it finds no match and
    /// jumps to the next period that has one, so "monthly on the 31st" silently fires
    /// only ~7 months a year. We instead CLAMP to the last valid day of the period
    /// (matching Apple Reminders): "monthly on the 31st" lands on 28/29/30 Feb and the
    /// 30th of a 30-day month, and "annually on 29 Feb" lands on 28 Feb in common years.
    func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date {
        switch recurrence {
        case .none:
            return scheduledDate
        case .hourly, .daily, .weekly:
            // These cadences match only components present in EVERY period (minute, hour,
            // weekday), so the system policy can never skip an occurrence — no clamp needed.
            let comps = recurrence.matchingComponents(from: scheduledDate, calendar: calendar)
            return calendar.nextDate(after: date, matching: comps,
                                     matchingPolicy: .nextTimePreservingSmallerComponents) ?? scheduledDate
        case .monthly:
            return Self.nextClamped(after: date, anchor: scheduledDate, steppingBy: .month, calendar: calendar)
        case .annually:
            return Self.nextClamped(after: date, anchor: scheduledDate, steppingBy: .year, calendar: calendar)
        }
    }

    /// Whether this reminder is OVERDUE — past its time and not yet done — and so wants
    /// attention. Single source (owner 2026-06-21) for the ruby "OVERDUE" card edge AND
    /// the "Expired" Sequence filter, so the timeline and the filter can never disagree.
    /// A REPEATING reminder is never overdue: its anchor sits in the past by design yet it
    /// always has a next occurrence ahead — its card shows the next due, not "OVERDUE".
    func isOverdue(now: Date) -> Bool {
        !isDone && !repeats && scheduledDate < now
    }

    /// The upcoming due instant to DISPLAY (owner 2026-06-21): the stored date while it
    /// is still ahead (so a manual "Done"/"skip" that advances it shows immediately),
    /// otherwise the live next occurrence — so a recurring card is never stale even if
    /// the user never acts on it. A one-shot just shows its scheduled instant.
    func effectiveNextDue(now: Date, calendar: Calendar = .current) -> Date {
        guard repeats else { return scheduledDate }
        return scheduledDate > now ? scheduledDate : nextOccurrence(after: now, calendar: calendar)
    }

    /// The first occurrence strictly after `date` for a `monthly` (`steppingBy: .month`)
    /// or `annually` (`steppingBy: .year`) cadence, clamping the anchor's day-of-month to
    /// the last valid day of any short period so no occurrence is skipped (owner
    /// 2026-06-21). Walks period-by-period from `date`; the bound only guards a
    /// pathological non-terminating search and is never reached in practice.
    private static func nextClamped(after date: Date, anchor: Date,
                                    steppingBy component: Calendar.Component,
                                    calendar: Calendar) -> Date {
        let a = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: anchor)
        guard let anchorDay = a.day else { return anchor }
        var probe = date
        for _ in 0..<800 {
            let p = calendar.dateComponents([.year, .month], from: probe)
            guard let year = p.year, let probeMonth = p.month else { return anchor }
            // Annually pins the anchor's month; monthly walks the probe's month.
            let month = (component == .year) ? (a.month ?? probeMonth) : probeMonth
            if let candidate = clampedDate(year: year, month: month, day: anchorDay,
                                           hour: a.hour ?? 0, minute: a.minute ?? 0, second: a.second ?? 0,
                                           calendar: calendar),
               candidate > date {
                return candidate
            }
            guard let stepped = calendar.date(byAdding: component, value: 1, to: probe) else { return anchor }
            probe = stepped
        }
        return anchor
    }

    /// Build a concrete instant for `year`/`month` at the anchor's day + time, clamping the
    /// day DOWN to the month's length (so day 31 in February becomes 28/29). Returns nil
    /// only if the calendar can't form the date at all.
    private static func clampedDate(year: Int, month: Int, day: Int,
                                    hour: Int, minute: Int, second: Int,
                                    calendar: Calendar) -> Date? {
        var firstOfMonth = DateComponents()
        firstOfMonth.year = year
        firstOfMonth.month = month
        firstOfMonth.day = 1
        guard let first = calendar.date(from: firstOfMonth),
              let range = calendar.range(of: .day, in: .month, for: first) else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = min(day, range.count)
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        return calendar.date(from: comps)
    }
}
