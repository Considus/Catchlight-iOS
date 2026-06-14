//
//  TextBlock.swift
//  CatchlightCore
//
//  A line/paragraph of prose inside a Take's ordered block list (D-035).
//  Carries a stable `id` so the block editor can diff, animate, and reorder
//  rows, and so a future block can be addressed independently. The sibling
//  block type is `ChecklistItem` (a check line); the two interleave freely as
//  `TakeBlock` cases.
//

import Foundation

public struct TextBlock: Identifiable, Codable, Equatable, Sendable {
    /// Stable identity for diffing / reorder animation across edits.
    public let id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}
