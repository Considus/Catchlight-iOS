//
//  ISO8601.swift
//  CatchlightCore
//
//  The single, canonical date format for everything Catchlight writes — both the
//  encrypted Take payload and the plaintext cloud-folder files. Defined once here
//  so every platform (iOS, macOS, future Web/Android) agrees byte-for-byte.
//
//  Format: `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` in UTC, POSIX locale, Gregorian calendar.
//  Example: `2026-05-28T07:00:00.000Z`.
//
//  Why a fixed `DateFormatter` rather than `JSONEncoder.DateEncodingStrategy.iso8601`
//  or `ISO8601DateFormatter`:
//    • Reproducible to the millisecond — conflict detection compares `modifiedAt`,
//      and second-only resolution would create avoidable ties.
//    • No locale/timezone leakage — `JSONEncoder`'s default reference-date Double
//      is an Apple-specific format and is explicitly forbidden by the brief (§4.1).
//    • Parses cleanly with JavaScript `new Date(str)` and Java `Instant.parse` after
//      trivial normalisation, satisfying the Roadmap §4 platform-agnostic rule.
//

import Foundation

public enum ISO8601 {
    /// The one and only formatter used for serialisation across the whole app.
    public static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return f
    }()

    public static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    public static func date(from string: String) -> Date? {
        if let d = formatter.date(from: string) { return d }
        return lenientDate(from: string)
    }

    /// Truncate a `Date` to millisecond precision — the wire format's resolution.
    /// `Date` natively carries sub-microsecond precision, so a value that has
    /// round-tripped through serialisation compares unequal to its in-memory
    /// original unless both are normalised. `Take` normalises its timestamps with
    /// this at creation and on mutation.
    public static func truncateToMilliseconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
    }

    /// Seconds-only fallback formatter (no fractional part), e.g. the literal
    /// examples in the spec ("2026-05-28T07:00:00Z").
    private static let secondsOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()

    /// Tolerant parse for valid ISO-8601 UTC variants other clients may emit
    /// (2026-06-10). Java's `Instant.toString()` produces 0/3/6/9 fractional
    /// digits, and `+00:00` is a legal UTC offset. Previously such timestamps
    /// parsed as nil — which made `SyncLock.isStale` treat another client's
    /// FRESH lock as stale (lock stealing) and quarantined otherwise-valid blobs.
    /// Canonical OUTPUT remains exactly `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`; this
    /// widens INPUT only.
    private static func lenientDate(from raw: String) -> Date? {
        // Shape: <date>T<time>[.fraction]<Z or ±HH[:]MM>
        guard raw.count >= 20, raw.count <= 40 else { return nil }
        let pattern = #"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:?\d{2})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) else {
            return nil
        }
        func group(_ i: Int) -> String? {
            guard let r = Range(match.range(at: i), in: raw) else { return nil }
            return String(raw[r])
        }
        guard let secondsPart = group(1),
              let base = secondsOnlyFormatter.date(from: secondsPart + "Z") else { return nil }

        var interval = base.timeIntervalSince1970

        if let frac = group(2) {
            // Pad/truncate to milliseconds: ".1" == 100ms, ".123456789" == 123ms.
            let ms3 = frac.padding(toLength: 3, withPad: "0", startingAt: 0).prefix(3)
            if let ms = Double(ms3) { interval += ms / 1000 }
        }

        if let offset = group(3), offset != "Z" {
            let sign: Double = offset.hasPrefix("-") ? -1 : 1
            let digits = offset.dropFirst().replacingOccurrences(of: ":", with: "")
            guard digits.count == 4,
                  let hours = Double(digits.prefix(2)),
                  let minutes = Double(digits.suffix(2)) else { return nil }
            interval -= sign * (hours * 3600 + minutes * 60)
        }
        return Date(timeIntervalSince1970: interval)
    }
}
