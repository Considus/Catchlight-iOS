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

    /// Local-notification scheduling (2026-06-10). Previously NOTHING invoked
    /// ReminderScheduler's schedule/cancel paths — a Take shaped into a
    /// Reminder showed its date label and no notification ever fired. Every
    /// save reconciles the pending request with the Take's current
    /// `timeReminder`; deletes cancel it. (Sync-applied writes go straight to
    /// the store and are reconciled when they next pass through this VM —
    /// acknowledged v1.0 limitation.)
    private let reminders: ReminderScheduler
    private var didRequestNotificationAuth = false

    init(store: TakeStore,
         spotlight: SpotlightIndexing = NoopSpotlightIndexer(),
         reminders: ReminderScheduler = ReminderScheduler()) {
        self.store = store
        self.spotlight = spotlight
        self.reminders = reminders
        reload()
    }

    /// Reconcile the OS notification request with the Take's current state.
    /// Cancel-then-schedule by the Take's UUID (the notification identifier),
    /// so a removed reminder cancels and an added/changed one re-registers.
    /// First-ever schedule requests authorization (§8.3: ask when the user
    /// adds their first reminder, not at launch).
    private func reconcileNotification(for take: Take) {
        reminders.cancelReminder(identifier: take.id.uuidString)
        guard take.timeReminder != nil else { return }
        if !didRequestNotificationAuth {
            didRequestNotificationAuth = true
            let reminders = self.reminders
            let snapshot = take
            Task {
                _ = await reminders.requestAuthorization()
                reminders.scheduleReminder(for: snapshot)
            }
        } else {
            reminders.scheduleReminder(for: take)
        }
    }

    // MARK: - Loading

    func reload() {
        do {
            let all = try store.allTakes()
            obie = all.first { $0.isObie }
            takes = all
                .filter { !$0.isObie }
                // Newest first; id as a DETERMINISTIC tie-break — createdAt is
                // millisecond-truncated, so same-instant creations can tie, and
                // Swift's sort is not stable (tied rows would shuffle between
                // reloads).
                .sorted {
                    if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                    return $0.id.uuidString > $1.id.uuidString
                }
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

    /// Surface a storage failure that happened outside this view model (e.g. a
    /// conflict resolution writing through the shared store). Routes through the
    /// same non-blocking strip as the VM's own errors.
    func reportStorageError(_ message: String) { lastError = message }

    // MARK: - Create / edit

    /// Create a fresh, blank Note Take and return it so the caller can open the
    /// edit surface on it immediately. NOT persisted (2026-06-10): the editor
    /// saves on dismiss, and a blank dismissed Take is discarded — previously the
    /// blank row was written to the store before any typing, so cancelling left a
    /// permanent "Untitled take" with no way to remove it.
    @discardableResult
    func createTake() -> Take {
        var take = Take()
        take.normaliseActivityFloor()
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
            reconcileNotification(for: updated)
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
            reminders.cancelReminder(identifier: take.id.uuidString)
            reload()
        } catch {
            lastError = "Couldn't delete that Take."
        }
    }

    /// Quietly remove a Take that may or may not have been persisted — used when
    /// the editor is dismissed with no content (blank-Take discard). Not-found is
    /// expected (the Take was never saved); other failures stay quiet too since
    /// there is nothing the user meant to keep.
    func discardIfPresent(_ take: Take) {
        guard (try? store.take(id: take.id)) != nil else { return }
        try? store.delete(id: take.id)
        spotlight.deindex(takeID: take.id)
        reminders.cancelReminder(identifier: take.id.uuidString)
        reload()
    }

    /// Toggle a Task's completion state. No-op for non-Tasks (completion is
    /// meaningless there; `normaliseActivityFloor` would clear it anyway).
    func toggleComplete(_ take: Take) {
        guard take.isTask else { return }
        var updated = take
        // Take-level completion (D-035): ticking the Take ticks every item; one
        // untouched item leaves the Take incomplete, so toggling drives all items
        // to the same new state.
        updated.setAllItemsComplete(!take.isComplete)
        save(updated)
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
        updated.setTask(isTask)
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
