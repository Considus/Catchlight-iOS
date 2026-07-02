//
//  TakeTransferMetadata.swift
//  CatchlightCore — lossless Markdown round-trip (D-088)
//
//  The machine-readable per-Take metadata embedded in a Markdown export's trailing
//  data block, so an export round-trips losslessly on import. The visible Markdown
//  stays the human view; this carries the fields prose can't hold — the EXACT
//  timestamps, the Obie flag, and the full reminder structures (both are Codable, so
//  recurrence / weekdays / radius / trigger all survive verbatim). One entry per Take,
//  in the same `createdAt`-ascending order as the visible `## …` sections.
//
//  Dates are encoded with the app's own `ISO8601` helper (millisecond precision,
//  matching the encrypted store) rather than JSONEncoder's default, so a Take's dates
//  are byte-identical whether it came from the store or a re-imported export.
//

import Foundation

struct TakeTransferMetadata: Codable {
    var createdAt: Date
    var modifiedAt: Date
    var isObie: Bool
    var timeReminder: TimeReminder?
    var locationReminder: LocationTrigger?

    init(from take: Take) {
        self.createdAt = take.createdAt
        self.modifiedAt = take.modifiedAt
        self.isObie = take.isObie
        self.timeReminder = take.timeReminder
        self.locationReminder = take.locationReminder
    }
}

/// Shared constants + coders for the trailing data block. Kept in one place so the
/// exporter and importer can never disagree on the fence text or the date format.
enum TakeTransfer {
    static let dataBlockOpen = "<!-- catchlight:data"
    static let dataBlockClose = "-->"

    /// Deterministic (sorted keys) so byte-exact export tests can pin the output;
    /// ISO-8601 with millisecond precision via the core's own helper.
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(ISO8601.string(from: date))
        }
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            guard let date = ISO8601.date(from: s) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath, debugDescription: "unparseable ISO date \(s)"))
            }
            return date
        }
        return d
    }
}
