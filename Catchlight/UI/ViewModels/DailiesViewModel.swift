//
//  DailiesViewModel.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  Owns the Dailies timeline: the full list of Takes, the current Obie, and the
//  add/edit/delete/toggle operations. Uses @Observable (iOS 17+) — NOT
//  ObservableObject — per the Phase 6 architecture decision. Talks only to the
//  CatchlightCore.TakeStore protocol, so it is identical whether the concrete store
//  is SQLCipher (production) or InMemoryTakeStore (previews / simulator-without-
//  entitlements).
//

import Foundation
import Observation
import CatchlightCore

@Observable
final class DailiesViewModel {
    /// All non-Obie Takes, newest first (the timeline reads top-down, most recent
    /// at the top beneath the pinned Obie).
    private(set) var takes: [Take] = []
    /// The single current Obie, pinned at the top of the list (nil if none).
    private(set) var obie: Take?
    /// Surfaced to the UI when a store operation fails; views may show a quiet note.
    private(set) var lastError: String?

    /// The underlying store. Exposed so conflict resolution (Task 6.15) can write
    /// the winning version through the same backend the timeline reads from.
    let store: TakeStore

    /// Task 6.19 — Spotlight surface. Injected so previews and tests can opt out
    /// of indexing (NoopSpotlightIndexer); production uses CoreSpotlightIndexer
    /// from Wiring. Every create/update goes through `save(_:)` and every
    /// delete through `delete(_:)`, so wiring at the VM level covers all paths.
    private let spotlight: SpotlightIndexing

    init(store: TakeStore, spotlight: SpotlightIndexing = NoopSpotlightIndexer()) {
        self.store = store
        self.spotlight = spotlight
        reload()
    }

    // MARK: - Loading

    func reload() {
        do {
            let all = try store.allTakes()
            obie = all.first { $0.isObie }
            takes = all
                .filter { !$0.isObie }
                .sorted { $0.createdAt > $1.createdAt }   // newest first
            lastError = nil
        } catch {
            lastError = "Couldn't load your Takes."
        }
    }

    /// True when the store holds nothing at all — drives the first-launch empty state.
    var isEmpty: Bool { obie == nil && takes.isEmpty }

    /// Clear the last storage error string (Task 3.9). Called by the error strip's
    /// Dismiss button and by the 5-second auto-dismiss timer. A no-op if no error
    /// is currently surfaced.
    func clearError() { lastError = nil }

    // MARK: - Create / edit

    /// Create a fresh, blank Note Take and return it so the caller can open the
    /// edit surface on it immediately.
    @discardableResult
    func createTake() -> Take {
        var take = Take()
        take.normaliseActivityFloor()
        save(take)
        return take
    }

    /// Persist edits to an existing Take (or a new one). Bumps `modifiedAt` and
    /// clears the seed flag on first edit (UX §12).
    func save(_ take: Take) {
        var updated = take
        updated.modifiedAt = Date()
        if updated.isSeeded { updated.isSeeded = false }
        updated.normaliseActivityFloor()
        do {
            try store.upsert(updated)
            // Spotlight (Task 6.19) — re-index every save (covers both create
            // and update paths since both funnel here). Fire-and-forget; the
            // store write is the authoritative outcome.
            spotlight.index(updated)
            reload()
        } catch {
            lastError = "Couldn't save that Take."
        }
    }

    func delete(_ take: Take) {
        do {
            try store.delete(id: take.id)
            // Spotlight (Task 6.19) — drop the item from the OS index so a
            // deleted Take can't be discovered via search.
            spotlight.deindex(takeID: take.id)
            reload()
        } catch {
            lastError = "Couldn't delete that Take."
        }
    }

    // MARK: - Activity-type toggles (petal fan applies these)

    /// Apply the petal-fan selection to a Take, enforcing the Note floor.
    func applyActivityTypes(to take: Take,
                            isNote: Bool,
                            isTask: Bool,
                            hasReminder: Bool,
                            isObie: Bool) {
        var updated = take
        updated.isNote = isNote
        updated.isTask = isTask
        if hasReminder, updated.timeReminder == nil {
            // Default a reminder to tomorrow morning; the edit surface refines it.
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            updated.timeReminder = TimeReminder(
                scheduledDate: tomorrow,
                notificationIdentifier: updated.id.uuidString
            )
        } else if !hasReminder {
            updated.timeReminder = nil
        }
        updated.normaliseActivityFloor()

        if isObie {
            // Persist the base edits first, then designate via the store's Obie rule.
            save(updated)
            designateObie(updated, replaceExisting: true)
        } else {
            if updated.isObie { updated.isObie = false }
            save(updated)
        }
    }

    // MARK: - Obie

    /// Long-press designates a Take as Obie. If one already exists and `replaceExisting`
    /// is false, the store throws `obieConflict` and we surface a confirmation need.
    func designateObie(_ take: Take, replaceExisting: Bool) {
        do {
            try store.setObie(id: take.id, replaceExisting: replaceExisting)
            reload()
        } catch StorageError.obieConflict(let existing) {
            pendingObieConflict = (newTake: take.id, existing: existing)
        } catch {
            lastError = "Couldn't set Obie."
        }
    }

    /// Set when a long-press would replace an existing Obie; the view shows a
    /// confirmation and then calls `confirmObieReplacement`.
    var pendingObieConflict: (newTake: UUID, existing: UUID)?

    func confirmObieReplacement() {
        guard let pending = pendingObieConflict else { return }
        pendingObieConflict = nil
        do {
            try store.setObie(id: pending.newTake, replaceExisting: true)
            reload()
        } catch {
            lastError = "Couldn't set Obie."
        }
    }

    func cancelObieReplacement() { pendingObieConflict = nil }
}
