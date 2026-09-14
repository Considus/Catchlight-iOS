//
//  TakeTransferMetadata.swift
//  CatchlightCore — lossless Markdown round-trip (D-104)
//
//  The machine-readable per-Take metadata embedded in a Markdown export's trailing
//  data block, so an export round-trips losslessly on import. The visible Markdown
//  stays the human view; this carries the fields prose can't hold — the EXACT
//  timestamps, the Obie flag, the Important flag, the manual timeline position, and
//  the full reminder structures (both are Codable, so
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

    /// 🚨 BOTH ADDED 2026-09-14, and both are OPTIONAL for one reason: an export
    /// written before this date has neither key, and Swift's synthesised decoder
    /// throws on a missing key rather than falling back to a property's default.
    /// Optional is therefore what keeps every export already sitting in somebody's
    /// folder readable. Do not "tidy" these into non-optionals.
    ///
    /// Why they were missing at all: the SYNC payload has carried both since v3, so
    /// `TakeRoundTripIdentityTests` was green and the encrypted round trip was
    /// genuinely lossless. The Markdown export is a second, narrower format, and it
    /// simply never gained them. The owner found it the hard way — he uses Important
    /// constantly, wipes and re-imports his own real Takes several times a week, and
    /// had been silently losing every flag for months without noticing.
    var isImportant: Bool?

    /// The manual timeline position. Carried as DATA rather than inferred from the
    /// order of the `## …` sections, because the visible document is deliberately
    /// sorted `createdAt` ascending as a reading order, and inferring position from
    /// file order would either break that or break after anyone edited the file by
    /// hand. `nil` means the Take has no manual position, which is the normal case.
    var manualOrder: Double?

    init(from take: Take) {
        self.createdAt = take.createdAt
        self.modifiedAt = take.modifiedAt
        self.isObie = take.isObie
        self.timeReminder = take.timeReminder
        self.locationReminder = take.locationReminder
        self.isImportant = take.isImportant
        self.manualOrder = take.manualOrder
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
