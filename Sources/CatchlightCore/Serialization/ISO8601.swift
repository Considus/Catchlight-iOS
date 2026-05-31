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
        // Tolerant fallback: accept seconds-only ISO 8601 (no fractional part),
        // e.g. the literal examples in the spec ("2026-05-28T07:00:00Z").
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone(identifier: "UTC")
        fallback.calendar = Calendar(identifier: .gregorian)
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return fallback.date(from: string)
    }
}
