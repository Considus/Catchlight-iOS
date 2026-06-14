//
//  ChecklistItem.swift
//  CatchlightCore
//
//  A single check item inside a Take (D-034 / D-035).
//
//  v1.0 STATUS: in active use. A check item is the payload of a `.check`
//  `TakeBlock`; a Take with one or more of them IS a Task (D-034). The struct is
//  unchanged from when it was forward-compat-only — only its role changed. The
//  Horizon-2 "promote check item to independent Take" action still targets one
//  of these cleanly (Roadmap §3, Horizon 2 + Decisions Log).
//
//  DELIBERATE OMISSIONS — DO NOT ADD:
//    • no `reminder` field   — reminders belong to Takes, not sub-items.
//    • no `linkedTakeId`      — promotion creates an INDEPENDENT Take; there is no
//                               linked/nested Take concept (Roadmap Decisions Log).
//  This struct must contain ONLY id + text + isComplete (tested in §12.2).
//

import Foundation

public struct ChecklistItem: Identifiable, Codable, Equatable, Sendable {
    /// Stable identity so a future promote-to-Take action can act on a specific item.
    public let id: UUID
    public var text: String
    public var isComplete: Bool

    public init(id: UUID = UUID(), text: String, isComplete: Bool = false) {
        self.id = id
        self.text = text
        self.isComplete = isComplete
    }
}
