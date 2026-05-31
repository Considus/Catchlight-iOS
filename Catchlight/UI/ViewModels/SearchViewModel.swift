//
//  SearchViewModel.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  Owns the search surface: the query string and the matching Takes. @Observable
//  (iOS 17+). Delegates the actual matching to TakeStore.search — FTS5 in the
//  production SQLCipher store, case-insensitive substring in the in-memory store.
//

import Foundation
import Observation
import CatchlightCore

@Observable
final class SearchViewModel {
    var query: String = "" {
        didSet { recompute() }
    }
    private(set) var results: [Take] = []

    private let store: TakeStore

    init(store: TakeStore) {
        self.store = store
    }

    func recompute() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        results = (try? store.search(trimmed)) ?? []
    }

    /// True only when the user has typed something but nothing matched — drives the
    /// "No takes match." empty state (distinct from the resting, empty-query state).
    var hasNoMatches: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && results.isEmpty
    }
}
