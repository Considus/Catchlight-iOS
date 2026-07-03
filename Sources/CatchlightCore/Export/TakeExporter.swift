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
    /// `(takes, exportedAt, timeZone)` so tests can pin the bytes. Export is Markdown
    /// ONLY (owner 2026-07-02 — the plain-text option was removed; Markdown reads fine
    /// as text AND round-trips, so a separate lossy format only invited a non-
    /// re-importable "backup"). Import still accepts `.txt`/`.rtf` for foreign notes.
    ///
    /// - Parameters:
    ///   - takes: Takes to export. Re-sorted by `createdAt` ascending so the
    ///            caller doesn't have to pre-sort.
    ///   - exportedAt: The export timestamp; injected so tests are deterministic.
    ///                 Defaults to `Date()` in production callers.
    ///   - timeZone: The zone Take-level dates render in (owner decision
    ///               2026-07-01: LOCAL time — a 09:00 reminder must read 09:00
    ///               in the export, not its UTC instant). Injected so the
    ///               byte-exact format tests stay deterministic; defaults to
    ///               the device zone. The file-level `exported:` header stays
    ///               ISO-UTC — it is file metadata, not a Take timestamp.
    public static func export(_ takes: [Take],
                              exportedAt: Date = Date(),
                              timeZone: TimeZone = .current) -> String {
        let sorted = takes.sorted { $0.createdAt < $1.createdAt }

        var out = preamble(count: sorted.count, exportedAt: exportedAt)

        for take in sorted {
            out += "\n"
            out += "## \(heading(for: take, timeZone: timeZone))\n"
            out += "\(body(for: take))\n"
        }

        // Lossless round-trip (D-104): a non-empty export appends ONE hidden data block
        // carrying each Take's exact timestamps / Obie / reminders, so import can
        // rebuild the individual Takes rather than collapse the file into one. It is an
        // HTML comment (invisible in any rendered Markdown). Metadata order matches the
        // visible sections (createdAt ascending).
        if !sorted.isEmpty {
            out += dataBlock(for: sorted)
        }

        return out
    }

    /// The trailing `<!-- catchlight:data … -->` block: a JSON array of per-Take
    /// metadata, one entry per visible section in the same order.
    private static func dataBlock(for sorted: [Take]) -> String {
        let metas = sorted.map { TakeTransferMetadata(from: $0) }
        guard let data = try? TakeTransfer.encoder().encode(metas),
              let json = String(data: data, encoding: .utf8) else {
            return ""   // metadata is additive; never fail an export over it
        }
        return "\n\(TakeTransfer.dataBlockOpen)\n\(json)\n\(TakeTransfer.dataBlockClose)\n"
    }

    /// File header: the pinned YAML frontmatter.
    private static func preamble(count: Int, exportedAt: Date) -> String {
        "---\nexported: \(isoUTC(exportedAt))\ntakes: \(count)\n---\n"
    }

    /// Render a Take's blocks in order: prose lines as-is, check items as
    /// `- [ ]` / `- [x]` (D-035). One block per line.
    static func body(for take: Take) -> String {
        take.blocks.map { block in
            switch block {
            case .text(let textBlock):
                return textBlock.text
            case .check(let item):
                let box = item.isComplete ? "[x]" : "[ ]"
                return "- \(box) \(item.text)"
            }
        }.joined(separator: "\n")
    }

    /// Suggested filename for the share sheet, e.g. `catchlight-2026-06-09.md`. Single
    /// timestamp granularity (day) — multiple same-day exports are disambiguated by the
    /// OS's "Save As" dialog.
    public static func suggestedFilename(exportedAt: Date = Date(),
                                         timeZone: TimeZone = .current) -> String {
        "catchlight-\(makeFormatter("yyyy-MM-dd", timeZone: timeZone).string(from: exportedAt)).md"
    }

    /// Whether a filename matches the export naming pattern. Used by the app target's
    /// stale-tmp-file sweep so it only ever deletes Catchlight exports. Still matches
    /// `.txt` as well as `.md` so any plain-text export written by an earlier build is
    /// swept from tmp too (owner 2026-06-21).
    public static func isExportFilename(_ name: String) -> Bool {
        name.hasPrefix("catchlight-") && (name.hasSuffix(".md") || name.hasSuffix(".txt"))
    }

    // MARK: - Heading

    /// H2 line for one Take. Activity precedence:
    ///   Reminder (timeReminder != nil) > Task > Note.
    /// — Reminder is the most specific qualifier so it owns the heading when
    /// present; the body text and any future per-Take view still show all the
    /// activity types via the focus-ring fan.
    static func heading(for take: Take, timeZone: TimeZone = .current) -> String {
        let ymd = makeFormatter("yyyy-MM-dd", timeZone: timeZone)
        let ymdHm = makeFormatter("yyyy-MM-dd HH:mm", timeZone: timeZone)
        let date = ymd.string(from: take.createdAt)
        if let reminder = take.timeReminder {
            return "Reminder — \(date) · 🔔 \(ymdHm.string(from: reminder.scheduledDate))\(recurrenceSuffix(for: reminder))"
        }
        if take.isTask {
            let suffix = take.isComplete ? " · ✓ Complete" : ""
            return "Task — \(date)\(suffix)"
        }
        return "Note — \(date)"
    }

    /// Human-readable repeat suffix for a REPEATING reminder — e.g.
    /// " · repeats weekly (Mon, Wed, Fri)" or " · repeats daily" (owner 2026-07-02: the
    /// recurrence already round-trips via the hidden data block, but wasn't visible in
    /// the heading). Empty for a one-shot. Weekday numbers are Gregorian (1 = Sun … 7 = Sat).
    private static func recurrenceSuffix(for reminder: TimeReminder) -> String {
        guard reminder.recurrence != .none else { return "" }
        var suffix = " · repeats \(reminder.recurrence.label.lowercased())"
        if reminder.recurrence == .weekly, !reminder.weekdays.isEmpty {
            let names = reminder.weekdays.sorted().compactMap(weekdayShortName)
            if !names.isEmpty { suffix += " (\(names.joined(separator: ", ")))" }
        }
        return suffix
    }

    private static let weekdayShortNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static func weekdayShortName(_ n: Int) -> String? {
        (1...7).contains(n) ? weekdayShortNames[n - 1] : nil
    }

    // MARK: - Date helpers
    //
    // Take-level dates (creation dates, reminder bell stamps, the filename date)
    // render in LOCAL time (owner decision 2026-07-01) — the previous all-UTC
    // rendering made a 09:00 reminder export as its UTC instant, which read as
    // simply wrong to the user. The formatters are built per export call (two
    // allocations per export, not per Take — the 2026-06-10 perf concern was the
    // per-Take rebuild) so the zone stays injectable for byte-exact tests.
    // The file-level `exported:` header keeps the cached ISO-UTC formatter: it
    // is machine-ish file metadata, not a Take timestamp.

    private static func makeFormatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = timeZone
        fmt.dateFormat = format
        return fmt
    }

    private static let isoUTCFormatter: DateFormatter = {
        let fmt = makeFormatter("yyyy-MM-dd'T'HH:mm:ss'Z'", timeZone: TimeZone(secondsFromGMT: 0)!)
        return fmt
    }()

    /// `yyyy-MM-ddTHH:mm:ssZ` — ISO 8601 in UTC, no fractional seconds.
    /// POSIX locale + Gregorian calendar so the output is stable regardless of
    /// the device's region / calendar settings. Header metadata only.
    static func isoUTC(_ date: Date) -> String { isoUTCFormatter.string(from: date) }
}
