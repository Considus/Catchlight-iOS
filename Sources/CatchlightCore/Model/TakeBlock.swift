//
//  TakeBlock.swift
//  CatchlightCore
//
//  One element of a Take's ordered content (D-035). A Take's body is
//  `[TakeBlock]`: prose lines (`.text`) and checkbox lines (`.check`) interleave
//  in any order, the way Apple Notes / Word behave. This replaces the old
//  `bodyText: String` + separate `checklistItems: [ChecklistItem]`, which could
//  only ever render "all text, then all checkboxes" — never interleaved.
//
//  A Take with at least one `.check` block IS a Task (D-034); there is no
//  separate "checklist" concept and no new type. `ChecklistItem` ({id, text,
//  isComplete}) is reused verbatim as the `.check` payload.
//
//  WIRE FORMAT: a tagged object keyed on `kind`, e.g.
//      { "kind": "text",  "id": "…", "text": "Buy film" }
//      { "kind": "check", "id": "…", "text": "Portra 400", "isComplete": false }
//  `id` rides on every block (stable identity for diffing, reorder animation,
//  and the Horizon-2 promote-to-Take action).
//

import Foundation

public enum TakeBlock: Identifiable, Codable, Equatable, Sendable {
    /// A line/paragraph of prose.
    case text(TextBlock)
    /// A checkbox line. Existing `ChecklistItem` ({id, text, isComplete}).
    case check(ChecklistItem)

    /// The stable id of whichever payload this block carries.
    public var id: UUID {
        switch self {
        case .text(let block): return block.id
        case .check(let item): return item.id
        }
    }

    /// The block's text, regardless of kind (prose or item label).
    public var text: String {
        switch self {
        case .text(let block): return block.text
        case .check(let item): return item.text
        }
    }

    /// True iff this is a `.check` block. Convenience for the derived `isTask`.
    public var isCheck: Bool {
        if case .check = self { return true }
        return false
    }

    // MARK: - Ergonomic constructors (seeds / previews / tests read cleanly)

    /// A prose line with a fresh id.
    public static func textLine(_ text: String) -> TakeBlock {
        .text(TextBlock(text: text))
    }

    /// A checkbox line with a fresh id.
    public static func checkItem(_ text: String, isComplete: Bool = false) -> TakeBlock {
        .check(ChecklistItem(text: text, isComplete: isComplete))
    }

    // MARK: - Codable (tagged object on `kind`)

    private enum Kind: String, Codable {
        case text, check
    }

    private enum CodingKeys: String, CodingKey {
        case kind, id, text, isComplete
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        let id = try c.decode(UUID.self, forKey: .id)
        let text = try c.decode(String.self, forKey: .text)
        switch kind {
        case .text:
            self = .text(TextBlock(id: id, text: text))
        case .check:
            // Tolerant of a missing flag so a partially-written payload still
            // decodes (mirrors the Take decoder's decodeIfPresent discipline).
            let done = try c.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false
            self = .check(ChecklistItem(id: id, text: text, isComplete: done))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let block):
            try c.encode(Kind.text, forKey: .kind)
            try c.encode(block.id, forKey: .id)
            try c.encode(block.text, forKey: .text)
        case .check(let item):
            try c.encode(Kind.check, forKey: .kind)
            try c.encode(item.id, forKey: .id)
            try c.encode(item.text, forKey: .text)
            try c.encode(item.isComplete, forKey: .isComplete)
        }
    }
}
