//
//  SequenceViewModel.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  Owns the Sequence (filtered) view: the active filter mode and the filtered,
//  ordered list of Takes. @Observable (iOS 17+). The Obie is pinned at the top of
//  every mode (UX §7). Filtering and ordering rules per the Phase 6 brief §7.
//

import Foundation
import Observation
import CatchlightCore

@Observable
final class SequenceViewModel {
    enum Filter: String, CaseIterable, Identifiable {
        case reminders = "Reminders"
        case tasks = "Tasks"
        case notes = "Notes"
        var id: String { rawValue }
    }

    var filter: Filter = .reminders {
        didSet { recompute() }
    }

    /// The Obie, always pinned at the top of every filter mode (nil if none).
    private(set) var obie: Take?
    /// The filtered, ordered Takes (excluding the Obie, which is shown separately).
    private(set) var results: [Take] = []

    private let store: TakeStore

    init(store: TakeStore) {
        self.store = store
        recompute()
    }

    func recompute() {
        let all = (try? store.allTakes()) ?? []
        obie = all.first { $0.isObie }
        let pool = all.filter { !$0.isObie }

        switch filter {
        case .reminders:
            // Takes with a Reminder active; excluded if they have no date.
            results = pool
                .filter { $0.timeReminder != nil }
                .sorted {
                    ($0.timeReminder?.scheduledDate ?? .distantFuture)
                        < ($1.timeReminder?.scheduledDate ?? .distantFuture)
                }   // due date, soonest first
        case .tasks:
            results = pool
                .filter { $0.isTask }
                .sorted { a, b in
                    if a.isComplete != b.isComplete { return !a.isComplete }   // incomplete first
                    return a.createdAt > b.createdAt
                }
        case .notes:
            // "Notes only" — Note active and no other activity type.
            results = pool
                .filter { $0.isNote && !$0.isTask && $0.timeReminder == nil }
                .sorted { $0.createdAt < $1.createdAt }   // creation order
        }
    }

    var isEmpty: Bool { obie == nil && results.isEmpty }
}
