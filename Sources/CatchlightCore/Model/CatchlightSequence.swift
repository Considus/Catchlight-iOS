//
//  CatchlightSequence.swift
//  CatchlightCore
//
//  A Sequence: a user-authored SAVED SEARCH over Takes (owner decision
//  2026-06-10 — filter-based "smart folder" model). "Not a folder. A story
//  built from captures" — the story is whatever currently matches the user's
//  own filter; membership is computed, never curated.
//
//  HISTORY: v1 modelled a Sequence as an ordered `takeIds` list. That field is
//  GONE (schema v2): hand-maintained membership lists contradicted the
//  capture-first ethos and were the worst-case data shape for multi-device
//  merging. v1 payloads (developer devices only — nothing shipped) decode with
//  an empty filter; the dead list is ignored.
//
//  NAMING: `Sequence` is a reserved Swift standard-library protocol name, so the
//  Swift type is `CatchlightSequence`. All user-facing strings and comments still
//  say "Sequence" — only the Swift type name differs (brief §4.7 naming note).
//

import Foundation

public struct CatchlightSequence: Identifiable, Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date

    /// The saved search this Sequence shows. Authored by the user (free text +
    /// dimension chips); see `SequenceFilter`.
    public var filter: SequenceFilter

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        filter: SequenceFilter = SequenceFilter()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.name = name
        self.createdAt = ISO8601.truncateToMilliseconds(createdAt)
        self.modifiedAt = ISO8601.truncateToMilliseconds(modifiedAt)
        self.filter = filter
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, createdAt, modifiedAt, filter
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // v1 payloads carry no schemaVersion and no filter (their `takeIds`
        // key is simply ignored).
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = ISO8601.truncateToMilliseconds(try c.decode(Date.self, forKey: .createdAt))
        modifiedAt = ISO8601.truncateToMilliseconds(try c.decode(Date.self, forKey: .modifiedAt))
        filter = try c.decodeIfPresent(SequenceFilter.self, forKey: .filter) ?? SequenceFilter()
        if schemaVersion < Self.currentSchemaVersion { schemaVersion = Self.currentSchemaVersion }
    }
}
