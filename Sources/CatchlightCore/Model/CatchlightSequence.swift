//
//  CatchlightSequence.swift
//  CatchlightCore
//
//  A Sequence: a user-defined, *ordered* collection of Takes (Phase 5 brief §4.7,
//  Brand Identity §1.4). "Not a folder. A story built from captures."
//
//  NAMING: `Sequence` is a reserved Swift standard-library protocol name, so the
//  Swift type is `CatchlightSequence`. All user-facing strings and comments still
//  say "Sequence" — only the Swift type name differs (brief §4.7 naming note).
//

import Foundation

public struct CatchlightSequence: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date

    /// Ordered list of Take ids. Order is meaningful — a Sequence has narrative.
    public var takeIds: [UUID]

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        takeIds: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.takeIds = takeIds
    }
}
