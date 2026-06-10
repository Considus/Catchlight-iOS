//
//  TakeExporter.swift
//  CatchlightCore — Task 6.22
//
//  Pure Markdown serialisation of a Take collection. Lives in the core module
//  so it has no UIKit dependency and can be unit-tested without a host app —
//  the export path is "your data is yours, always," and that promise has to
//  hold even when StoreKit / iCloud / the network are unavailable. The output
//  format is pinned by `App_Store_Connect_Decisions_v1.0.md §5` and must not
//  drift without an explicit decision update; downstream import tools (and
//  future per-Take export in v1.1) will read what this writes today.
//
//  Format (exact):
//
//      ---
//      exported: 2026-06-09T14:32:00Z
//      takes: 42
//      ---
//
//      ## Note — 2026-05-14
//      Buy film for the weekend shoot
//
//      ## Task — 2026-05-15 · ✓ Complete
//      Call the framer back
//
//      ## Reminder — 2026-05-16 · 🔔 2026-05-20 09:00
//      Pick up prints
//
//  Sort order: `createdAt` ascending (oldest first — matches `allTakes()`).
//

import Foundation

public enum TakeExporter {

    /// Build the Markdown payload for sharing. Pure: deterministic for a given
    /// `(takes, exportedAt)` pair so tests can pin the timestamp.
    ///
    /// - Parameters:
    ///   - takes: Takes to export. Re-sorted by `createdAt` ascending so the
    ///            caller doesn't have to pre-sort.
    ///   - exportedAt: The export timestamp; injected so tests are deterministic.
    ///                 Defaults to `Date()` in production callers.
    public static func export(_ takes: [Take], exportedAt: Date = Date()) -> String {
        let sorted = takes.sorted { $0.createdAt < $1.createdAt }

        var out = ""
        out += "---\n"
        out += "exported: \(Self.isoUTC(exportedAt))\n"
        out += "takes: \(sorted.count)\n"
        out += "---\n"

        for take in sorted {
            out += "\n"
            out += "## \(heading(for: take))\n"
            out += "\(take.bodyText)\n"
        }

        return out
    }

    /// Suggested filename for the share sheet, e.g. `catchlight-2026-06-09.md`.
    /// Always `.md`. Single timestamp granularity (day) — multiple same-day
    /// exports are disambiguated by the OS's "Save As" dialog.
    public static func suggestedFilename(exportedAt: Date = Date()) -> String {
        "catchlight-\(ymdFormatter.string(from: exportedAt)).md"
    }

    /// Whether a filename matches the export naming pattern. Used by the app
    /// target's stale-tmp-file sweep so it only ever deletes Catchlight exports.
    public static func isExportFilename(_ name: String) -> Bool {
        name.hasPrefix("catchlight-") && name.hasSuffix(".md")
    }

    // MARK: - Heading

    /// H2 line for one Take. Activity precedence:
    ///   Reminder (timeReminder != nil) > Task > Note.
    /// — Reminder is the most specific qualifier so it owns the heading when
    /// present; the body text and any future per-Take view still show all the
    /// activity types via the petal fan.
    static func heading(for take: Take) -> String {
        let date = ymd(take.createdAt)
        if let reminder = take.timeReminder {
            return "Reminder — \(date) · 🔔 \(ymdHm(reminder.scheduledDate))"
        }
        if take.isTask {
            let suffix = take.isComplete ? " · ✓ Complete" : ""
            return "Task — \(date)\(suffix)"
        }
        return "Note — \(date)"
    }

    // MARK: - Date helpers
    //
    // Formatters are CACHED as statics (2026-06-10): `DateFormatter` init is one
    // of Foundation's most expensive allocations, and `ymd` previously built a
    // fresh one per Take per export. `DateFormatter` is thread-safe on modern
    // OS releases, matching the pattern already used by `ISO8601.formatter`.

    private static func makeUTCFormatter(_ format: String) -> DateFormatter {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = format
        return fmt
    }

    private static let isoUTCFormatter = makeUTCFormatter("yyyy-MM-dd'T'HH:mm:ss'Z'")
    private static let ymdFormatter = makeUTCFormatter("yyyy-MM-dd")
    private static let ymdHmFormatter = makeUTCFormatter("yyyy-MM-dd HH:mm")

    /// `yyyy-MM-ddTHH:mm:ssZ` — ISO 8601 in UTC, no fractional seconds.
    /// POSIX locale + Gregorian calendar so the output is stable regardless of
    /// the device's region / calendar settings.
    static func isoUTC(_ date: Date) -> String { isoUTCFormatter.string(from: date) }

    /// `yyyy-MM-dd` in UTC. Creation dates in the heading are always rendered
    /// in UTC so an export looks identical regardless of where the device is.
    static func ymd(_ date: Date) -> String { ymdFormatter.string(from: date) }

    /// `yyyy-MM-dd HH:mm` in UTC. Used for the reminder bell stamp.
    static func ymdHm(_ date: Date) -> String { ymdHmFormatter.string(from: date) }
}
