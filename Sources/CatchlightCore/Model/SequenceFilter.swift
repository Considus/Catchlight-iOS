//
//  SequenceFilter.swift
//  CatchlightCore — filter-based Sequences (2026-06-10)
//
//  A Sequence is a SAVED SEARCH ("smart folder"), per the owner's decision of
//  2026-06-10: Takes flow in and out automatically, nothing is filed by hand.
//  The filter is authored by the user — free text in their own words, plus
//  optional dimension chips (activity type, completion, month) that compose
//  with AND semantics. There are no predefined categories anywhere: the chips
//  are dimensions of the user's own data, never canned folders.
//
//  Matching is PURE and platform-agnostic so it can be unit-tested directly
//  and reused by any future client. Month bucketing uses the supplied calendar
//  (callers pass the user's local calendar — "June" means the user's June).
//

import Foundation

public struct SequenceFilter: Codable, Equatable, Sendable {

    /// Free-text term. Case-insensitive substring match against the body text —
    /// the SAME semantics as `TakeStore.search`, so "what you searched" and
    /// "what the Sequence shows" can never disagree.
    public var text: String

    // Dimension chips — each `true` adds a constraint; `false` means "don't
    // care". All active constraints must hold (AND).

    /// Takes shaped as Tasks.
    public var requireTask: Bool
    /// Takes carrying a time reminder.
    public var requireReminder: Bool
    /// Pure notes: Note active and no other activity type (mirrors the
    /// timeline's vocabulary).
    public var requireNoteOnly: Bool
    /// Completed Tasks ("Done").
    public var requireCompleted: Bool

    /// Month buckets as "yyyy-MM" keys (e.g. "2026-06"), matched against the
    /// Take's `createdAt` in the caller's calendar. Multiple months are OR-ed
    /// within this dimension, then AND-ed with everything else.
    public var months: [String]

    public init(text: String = "",
                requireTask: Bool = false,
                requireReminder: Bool = false,
                requireNoteOnly: Bool = false,
                requireCompleted: Bool = false,
                months: [String] = []) {
        self.text = text
        self.requireTask = requireTask
        self.requireReminder = requireReminder
        self.requireNoteOnly = requireNoteOnly
        self.requireCompleted = requireCompleted
        self.months = months
    }

    // Tolerant decoding: every field has a default so future fields never
    // break old payloads (same discipline as Take).
    enum CodingKeys: String, CodingKey {
        case text, requireTask, requireReminder, requireNoteOnly, requireCompleted, months
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        requireTask = try c.decodeIfPresent(Bool.self, forKey: .requireTask) ?? false
        requireReminder = try c.decodeIfPresent(Bool.self, forKey: .requireReminder) ?? false
        requireNoteOnly = try c.decodeIfPresent(Bool.self, forKey: .requireNoteOnly) ?? false
        requireCompleted = try c.decodeIfPresent(Bool.self, forKey: .requireCompleted) ?? false
        months = try c.decodeIfPresent([String].self, forKey: .months) ?? []
    }

    /// True when the filter imposes no constraint at all (matches everything).
    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !requireTask && !requireReminder && !requireNoteOnly && !requireCompleted
            && months.isEmpty
    }

    // MARK: - Matching

    public func matches(_ take: Take, calendar: Calendar = .current) -> Bool {
        if requireTask && !take.isTask { return false }
        if requireReminder && take.timeReminder == nil { return false }
        if requireNoteOnly && (take.isTask || take.timeReminder != nil) { return false }
        if requireCompleted && !(take.isTask && take.isComplete) { return false }
        if !months.isEmpty,
           !months.contains(Self.monthKey(for: take.createdAt, calendar: calendar)) {
            return false
        }
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !term.isEmpty && !take.bodyText.lowercased().contains(term) { return false }
        return true
    }

    /// "yyyy-MM" bucket key for a date in the given calendar.
    public static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// A human-readable summary of the active constraints, used as the default
    /// Sequence name when the user keeps a filter without typing one
    /// ("darkroom", "Tasks · June 2026", …).
    public func summary(monthLabel: (String) -> String) -> String {
        var parts: [String] = []
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty { parts.append(term) }
        if requireTask { parts.append("Tasks") }
        if requireReminder { parts.append("Reminders") }
        if requireNoteOnly { parts.append("Notes") }
        if requireCompleted { parts.append("Done") }
        parts.append(contentsOf: months.map(monthLabel))
        return parts.isEmpty ? "Everything" : parts.joined(separator: " · ")
    }
}
