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

    /// Add new conflicts. Dedup is by Take id, but an INCOMING pair REPLACES a
    /// pending pair for the same id (2026-06-10): if either side changed between
    /// syncs, the user must resolve against the newest snapshot — the previous
    /// keep-the-old-pair behaviour could upsert a stale winner over a newer row.
    /// Safe to call repeatedly with the same SyncReport (idempotent).
    func enqueue(_ conflicts: [(local: Take, remote: Take)]) {
        var added = 0
        for pair in conflicts {
            if let idx = pending.firstIndex(where: { $0.local.id == pair.local.id }) {
                pending[idx] = pair
            } else {
                pending.append(pair)
                added += 1
            }
        }
        // Record newly-surfaced conflicts to the content-free diagnostics log (D-085) — a
        // count only, no Take content (the banner shows the same count).
        if added > 0 {
            DiagnosticsLog.shared.record(.conflict,
                "\(added) Take\(added == 1 ? "" : "s") changed on another device.")
        }
    }

    /// Resolve a single conflict by writing the chosen winner to the store and
    /// removing it from the queue. No-op if the id is no longer pending (e.g. the
    /// user resolved it on another row first).
    func resolve(id: UUID, keepLocal: Bool, store: TakeStore) throws {
        guard let idx = pending.firstIndex(where: { $0.local.id == id }) else { return }
        let pair = pending[idx]
        var winner = keepLocal ? pair.local : pair.remote
        // Stamp the resolution as a FRESH edit so the chosen version wins at the cloud
        // (owner-reported 2026-06-27). Without this the winner keeps its old `modifiedAt`,
        // which is ≤ the last-sync watermark — so `pushOutbound` never re-uploads it, the
        // divergent remote copy survives, and the next `pullInbound` re-detects the SAME
        // conflict via the `(localChanged:false, remoteChanged:false)` branch. Resolving
        // then never sticks: the conflict re-surfaces on every sync. Bumping `modifiedAt`
        // makes the next sync push the winner over the remote and the pull see `keepLocal`.
        winner.modifiedAt = Date()
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
