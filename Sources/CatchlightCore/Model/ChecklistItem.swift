//
//  ChecklistItem.swift
//  CatchlightCore
//
//  A single checklist item inside a Take (Phase 5 brief §4.5).
//
//  v1.0 STATUS: the `checklistItems` array on Take is always empty in v1.0; this
//  struct exists for the Horizon-2 "promote checklist item to independent Take"
//  feature (Roadmap §3, Horizon 2 + Decisions Log).
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
