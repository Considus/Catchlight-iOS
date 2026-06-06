//
//  ConflictQueue.swift
//  Catchlight (iOS app target) — Phase 6 UI, Task 6.15
//
//  Holds the live list of sync conflicts surfaced by `SyncEngine.pullInbound()`.
//  Populated by `BackgroundSyncCoordinator` after every background sync; read by
//  `DailiesView` (for the banner) and `ConflictResolutionView` (for the picker).
//
//  Deliberately not persisted to disk. If the user dismisses the sheet without
//  resolving every entry, the next sync will re-detect the same conflicts and
//  re-enqueue them — there's no value in serialising Take pairs outside the
//  encrypted store. Dedup is by Take id so re-enqueueing is idempotent.
//

import Foundation
import Observation
import CatchlightCore

@Observable
@MainActor
final class ConflictQueue {

    /// Unresolved conflicts in the order they were surfaced (oldest first). Each
    /// pair is the same shape produced by `SyncEngine.pullInbound()`.
    private(set) var pending: [(local: Take, remote: Take)] = []

    /// Add new conflicts, skipping any whose `local.id` is already pending. Safe to
    /// call repeatedly — the same SyncReport can be enqueued without growing the queue.
    func enqueue(_ conflicts: [(local: Take, remote: Take)]) {
        let existing = Set(pending.map(\.local.id))
        let fresh = conflicts.filter { !existing.contains($0.local.id) }
        pending.append(contentsOf: fresh)
    }

    /// Resolve a single conflict by writing the chosen winner to the store and
    /// removing it from the queue. No-op if the id is no longer pending (e.g. the
    /// user resolved it on another row first).
    func resolve(id: UUID, keepLocal: Bool, store: TakeStore) throws {
        guard let idx = pending.firstIndex(where: { $0.local.id == id }) else { return }
        let pair = pending[idx]
        let winner = keepLocal ? pair.local : pair.remote
        try store.upsert(winner)
        pending.remove(at: idx)
    }

    /// Remove a conflict without writing either version — "Skip for now" in the UI.
    /// The next sync will re-surface the same conflict if it's still unresolved upstream.
    func skip(id: UUID) {
        pending.removeAll { $0.local.id == id }
    }

    /// Clear every pending conflict without writing anything. Used by the empty-state
    /// auto-dismiss and by tests.
    func dismissAll() { pending.removeAll() }
}
