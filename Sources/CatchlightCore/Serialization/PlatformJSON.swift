//
//  PlatformJSON.swift
//  CatchlightCore
//
//  The platform-agnostic JSON codec. Every byte Catchlight serialises — the Take
//  payload that gets encrypted, the cloud envelope, the manifest, the account
//  metadata — goes through here. This is the concrete mechanism that satisfies the
//  non-negotiable "platform-agnostic from day one" principle (Phase 5 brief §2.4,
//  Roadmap §4):
//
//    • Dates: encoded/decoded as explicit ISO-8601 strings via `ISO8601` (NOT the
//      JSONEncoder default, which emits an Apple-specific reference-date Double).
//    • Key order: `.sortedKeys` — deterministic output so that HMAC-over-bytes is
//      reproducible and diffable, and so two platforms produce identical files.
//    • Slashes: `.withoutEscapingSlashes` — avoids `\/` noise; standard JSON.
//    • Data: `Data` fields are Base64 (JSONEncoder default), which is portable.
//
//  Nothing here uses NSKeyedArchiver, binary plists, or Core Data formats.
//

import Foundation

public enum PlatformJSON {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, enc in
            var container = enc.singleValueContainer()
            try container.encode(ISO8601.string(from: date))
        }
        encoder.dataEncodingStrategy = .base64
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = ISO8601.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected ISO-8601 UTC date, got '\(raw)'"
                )
            }
            return date
        }
        decoder.dataDecodingStrategy = .base64
        return decoder
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try makeEncoder().encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try makeDecoder().decode(type, from: data)
    }
}
