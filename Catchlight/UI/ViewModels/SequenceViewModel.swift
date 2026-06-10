//
//  SequenceViewModel.swift
//  Catchlight (iOS app target) — filter-based Sequences (2026-06-10)
//
//  Owns the Sequence tab: the user's SAVED SEARCHES and the live results of
//  the selected one. @Observable (iOS 17+). The previous version offered three
//  hard-coded filter pills (Reminders / Tasks / Notes) — exactly the kind of
//  predefined category the product ethos rejects; pills are now the user's own
//  kept filters, created from the Search surface ("Keep as Sequence").
//
//  Membership is COMPUTED via `SequenceFilter.matches` on every recompute —
//  Takes flow in and out as they change; nothing is filed or maintained.
//  The Obie stays pinned at the top of every Sequence (UX §7).
//

import Foundation
import Observation
import CatchlightCore

@Observable
final class SequenceViewModel {

    /// All saved Sequences, oldest first (creation order — the user's shelf).
    private(set) var sequences: [CatchlightSequence] = []

    /// The selected Sequence's id (nil when none exist).
    var selectedId: UUID? {
        didSet { recompute() }
    }

    /// The Obie, always pinned at the top (nil if none).
    private(set) var obie: Take?
    /// Live results of the selected Sequence's filter (excluding the Obie).
    private(set) var results: [Take] = []

    private let store: TakeStore

    init(store: TakeStore) {
        self.store = store
        recompute()
    }

    var selectedSequence: CatchlightSequence? {
        sequences.first { $0.id == selectedId }
    }

    func recompute() {
        sequences = (try? store.allSequences()) ?? []
        // Keep the selection valid: fall back to the first Sequence, or none.
        if selectedId == nil || !sequences.contains(where: { $0.id == selectedId }) {
            // Direct ivar-style fallback (avoid didSet recursion via the
            // property observer — assign only when it actually changes).
            let fallback = sequences.first?.id
            if selectedId != fallback {
                selectedId = fallback
                return   // didSet re-enters recompute with the new selection
            }
        }

        let all = (try? store.allTakes()) ?? []
        obie = all.first { $0.isObie }

        guard let filter = selectedSequence?.filter else {
            results = []
            return
        }
        results = all
            .filter { !$0.isObie && filter.matches($0) }
            .sorted { $0.createdAt > $1.createdAt }   // newest first, like the timeline
    }

    /// Delete a saved Sequence (the filter only — never any Takes).
    func deleteSequence(_ sequence: CatchlightSequence) {
        try? store.deleteSequence(id: sequence.id)
        if selectedId == sequence.id { selectedId = nil }
        recompute()
    }

    /// No Sequences saved yet — drives the create-from-Search hint.
    var hasNoSequences: Bool { sequences.isEmpty }

    /// Selected Sequence exists but currently matches nothing.
    var isEmpty: Bool { obie == nil && results.isEmpty }
}
