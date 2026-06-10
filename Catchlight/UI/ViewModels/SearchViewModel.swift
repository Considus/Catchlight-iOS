//
//  SearchViewModel.swift
//  Catchlight (iOS app target) — Phase 6 UI, filter-based Sequences 2026-06-10
//
//  Owns the search surface: a live `SequenceFilter` (free text + dimension
//  chips) and the matching Takes. @Observable (iOS 17+). Matching is the pure
//  `SequenceFilter.matches` — the SAME predicate saved Sequences use, so what
//  you see when searching is exactly what a kept Sequence will show.
//
//  Search doubles as the SEQUENCE CREATION surface ("a Sequence is a saved
//  search"): when the filter is non-empty, the view offers "Keep as Sequence",
//  which snapshots the current filter into a CatchlightSequence.
//

import Foundation
import Observation
import CatchlightCore

@Observable
final class SearchViewModel {

    var query: String = "" {
        didSet { recompute() }
    }

    // Dimension chips. Mutually compatible (AND-composed); month chips OR
    // within the month dimension. No predefined folders — these are dimensions
    // of the user's own data.
    var requireTask = false { didSet { recompute() } }
    var requireReminder = false { didSet { recompute() } }
    var requireNoteOnly = false { didSet { recompute() } }
    var requireCompleted = false { didSet { recompute() } }
    var selectedMonths: Set<String> = [] { didSet { recompute() } }

    private(set) var results: [Take] = []

    let store: TakeStore

    init(store: TakeStore) {
        self.store = store
    }

    /// The filter the current UI state describes.
    var activeFilter: SequenceFilter {
        SequenceFilter(
            text: query,
            requireTask: requireTask,
            requireReminder: requireReminder,
            requireNoteOnly: requireNoteOnly,
            requireCompleted: requireCompleted,
            months: selectedMonths.sorted()
        )
    }

    /// Month chips offered to the user — derived from the months their own
    /// Takes actually span (most recent first, capped), never a canned list.
    var monthOptions: [String] {
        let all = (try? store.allTakes()) ?? []
        let keys = Set(all.map { SequenceFilter.monthKey(for: $0.createdAt) })
        return keys.sorted(by: >).prefix(12).map { $0 }
    }

    func recompute() {
        let filter = activeFilter
        guard !filter.isEmpty else {
            results = []
            return
        }
        let all = (try? store.allTakes()) ?? []
        results = all
            .filter { filter.matches($0) }
            .sorted { $0.createdAt > $1.createdAt }   // newest first, like the timeline
    }

    func toggleMonth(_ key: String) {
        if selectedMonths.contains(key) { selectedMonths.remove(key) } else { selectedMonths.insert(key) }
    }

    func clearFilter() {
        query = ""
        requireTask = false
        requireReminder = false
        requireNoteOnly = false
        requireCompleted = false
        selectedMonths = []
    }

    /// True only when the user has expressed a filter but nothing matched —
    /// drives the "No takes match." empty state (distinct from the resting state).
    var hasNoMatches: Bool { !activeFilter.isEmpty && results.isEmpty }

    /// Whether "Keep as Sequence" should be offered.
    var canKeepAsSequence: Bool { !activeFilter.isEmpty }

    /// Snapshot the current filter as a saved Sequence. Returns the new
    /// Sequence, or nil if the filter is empty or the write failed.
    @discardableResult
    func keepAsSequence() -> CatchlightSequence? {
        let filter = activeFilter
        guard !filter.isEmpty else { return nil }
        let sequence = CatchlightSequence(
            name: filter.summary(monthLabel: Self.monthLabel(forKey:)),
            filter: filter
        )
        do {
            try store.upsert(sequence)
            return sequence
        } catch {
            return nil
        }
    }

    /// "2026-06" → "June 2026" in the user's locale.
    static func monthLabel(forKey key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[1]) else { return key }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        guard let date = Calendar.current.date(from: components) else { return key }
        return Self.monthLabelFormatter.string(from: date)
    }

    private static let monthLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return f
    }()
}
