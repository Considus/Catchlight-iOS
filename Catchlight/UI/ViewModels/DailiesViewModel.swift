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
    /// Surfaced to the UI when a store operation fails; views may show a quiet note. Each
    /// non-nil value is also recorded to the content-free diagnostics log (D-085) so it shows
    /// in Notice History and the export. These messages are static/generic — no Take content.
    private(set) var lastError: String? {
        didSet { if let lastError { DiagnosticsLog.shared.record(.storage, lastError) } }
    }

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

    /// Called after a USER-initiated local mutation (save / delete / import / Obie) so
    /// the app can push it promptly (owner 2026-07-02). NOT fired by sync-applied writes
    /// or `reload()`, so it can't loop with an inbound sync. Wired by `AppModel.rebind`.
    var onLocalChange: (() -> Void)?

    /// Fire the local-change hook (nil-safe).
    private func notifyLocalChange() { onLocalChange?() }

    /// - Parameter notificationAuthPreflighted: TEST SEAM ONLY. When true the VM
    ///   starts as if the one-time notification-auth request has already run, so
    ///   `reconcileNotification` takes its deterministic SYNCHRONOUS scheduling
    ///   branch instead of spawning the first-reminder `Task { await
    ///   requestAuthorization() }`. Defaults to false — production is unchanged
    ///   (the app still asks for auth on the user's first reminder). Tests set it
    ///   true so scheduling is observable in-line and no deferred Task outlives the
    ///   test (the async branch wedged the 18.5 sim's runner — 2026-07-02).
    init(store: TakeStore,
         spotlight: SpotlightIndexing = NoopSpotlightIndexer(),
         reminders: ReminderScheduler = ReminderScheduler(),
         notificationAuthPreflighted: Bool = false) {
        self.store = store
        self.spotlight = spotlight
        self.reminders = reminders
        self.didRequestNotificationAuth = notificationAuthPreflighted
        reload()
    }

    /// Reconcile the OS notification request with the Take's current state.
    /// Cancel-then-schedule by the Take's UUID (the notification identifier),
    /// so a removed reminder cancels and an added/changed one re-registers.
    /// First-ever schedule requests authorization (§8.3: ask when the user
    /// adds their first reminder, not at launch).
    private func reconcileNotification(for take: Take) {
        reminders.cancelReminder(identifier: take.id.uuidString)   // clears time + #loc ids
        // A Take may carry a "when", a "where", or both — schedule whichever it has.
        guard take.timeReminder != nil || take.locationReminder != nil else { return }
        if !didRequestNotificationAuth {
            didRequestNotificationAuth = true
            let reminders = self.reminders
            let snapshot = take
            Task {
                _ = await reminders.requestAuthorization()
                reminders.scheduleReminder(for: snapshot)
                reminders.scheduleLocationReminder(for: snapshot)
            }
        } else {
            reminders.scheduleReminder(for: take)
            reminders.scheduleLocationReminder(for: take)
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
    /// permanent "Untitled Take" with no way to remove it.
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
            notifyLocalChange()
        } catch {
            lastError = "Couldn't save that Take."
        }
    }

    /// Like `save`, but reflects the edit IN PLACE (no full `reload()`), so a swipe action
    /// re-renders just that one row instead of rebuilding + re-sorting the whole timeline —
    /// the source of the swipe "jank" (owner 2026-06-27). Safe ONLY when the edit doesn't
    /// change the Take's sort position or Obie membership (true for mark-done: `createdAt`
    /// is untouched and `isObie` isn't changed). Falls back to `reload()` if the Take isn't
    /// already on screen.
    private func saveInPlace(_ take: Take) {
        var updated = take
        updated.modifiedAt = Date()
        if updated.isSeeded { updated.isSeeded = false }
        updated.normaliseActivityFloor()
        do {
            try store.upsert(updated)
            spotlight.index(updated)
            reconcileNotification(for: updated)
            if obie?.id == updated.id {
                obie = updated
            } else if let i = takes.firstIndex(where: { $0.id == updated.id }) {
                takes[i] = updated
            } else {
                reload()
            }
            notifyLocalChange()
        } catch {
            lastError = "Couldn't save that Take."
        }
    }

    /// Bulk-insert imported Takes (owner 2026-06-22). Unlike `save`, this does NOT
    /// bump `modifiedAt` — the importer set `createdAt`/`modifiedAt` from the file so
    /// the note slots into the timeline by when it was written — and it reloads ONCE
    /// for the whole batch. Returns how many were inserted. New ids ⇒ never overwrites
    /// existing Takes; the next sync pass pushes them out like any local edit.
    @discardableResult
    func importTakes(_ takes: [Take]) -> Int {
        var inserted = 0
        for take in takes {
            var t = take
            t.normaliseActivityFloor()
            do {
                try store.upsert(t)
                spotlight.index(t)
                inserted += 1
            } catch {
                lastError = "Couldn't import one of the notes."
            }
        }
        if inserted > 0 { reload(); notifyLocalChange() }
        return inserted
    }

    func delete(_ take: Take) {
        do {
            try store.delete(id: take.id)
            // Spotlight (Task 6.19) — drop the item from the OS index so a
            // deleted Take can't be discovered via search.
            spotlight.deindex(takeID: take.id)
            reminders.cancelReminder(identifier: take.id.uuidString)
            // In-place removal (owner 2026-06-27): drop just this row instead of a full
            // `reload()` re-fetch + re-sort of every Take. The store write is already the
            // authoritative outcome; removing the single element lets the timeline collapse
            // smoothly under the caller's swipe/delete animation rather than rebuilding the
            // whole VStack — the source of the swipe "jank" (the pinned Obie wasn't in the
            // VStack, which is why deleting IT always looked smooth).
            if obie?.id == take.id { obie = nil }
            else { takes.removeAll { $0.id == take.id } }
            notifyLocalChange()
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

    /// Opt-in auto-cleanup sweep (owner 2026-06-19): delete finished, note-free Takes
    /// that have been untouched longer than the user's chosen window. The eligibility
    /// rule lives in `Take.isAutoCleanupEligible` (protects notes, in-progress Takes,
    /// and the Obie). A `nil` window (Settings = Never) is a no-op, so cleanup is
    /// strictly opt-in. Tears each match down through the same Spotlight/reminder path
    /// as `delete`, reloading once. `now` is injected for tests. Returns the count.
    @discardableResult
    func runAutoCleanup(olderThan maxAge: TimeInterval?, now: Date = Date()) -> Int {
        guard let maxAge else { return 0 }
        let all = (try? store.allTakes()) ?? []
        let doomed = all.filter { $0.isAutoCleanupEligible(olderThan: maxAge, now: now) }
        guard !doomed.isEmpty else { return 0 }
        var deleted = 0
        var failed = 0
        for take in doomed {
            do {
                try store.delete(id: take.id)
                // De-index Spotlight + cancel the reminder ONLY after the authoritative
                // store delete succeeds (owner 2026-06-21) — previously a swallowed
                // `try?` delete still ran these, leaving a de-indexed but still-present
                // Take (unsearchable yet on the timeline) with no signal of the failure.
                spotlight.deindex(takeID: take.id)
                reminders.cancelReminder(identifier: take.id.uuidString)
                deleted += 1
            } catch {
                failed += 1
            }
        }
        if failed > 0 {
            // Cleanup is best-effort; surface a quiet note rather than fail silently. The
            // un-deleted Takes are still eligible, so the next sweep (next app open) retries.
            lastError = "Some finished Takes couldn't be cleaned up — they'll be retried."
        }
        if deleted > 0 { reload() }
        return deleted
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

    /// Toggle the WHOLE Take done/not-done — Tasks AND reminders (owner 2026-06-18,
    /// [[catchlight-take-colour-system]]). One "Mark as done" ticks every item and
    /// flips any reminder's `isDone`, so a Take that is both settles in one move; the
    /// card then reads the done grey. The reminder-done state is otherwise unreachable.
    func toggleDone(_ take: Take) {
        guard take.canBeMarkedDone else { return }
        // A REPEATING reminder is never permanently "done" (owner 2026-06-21): marking it
        // done completes the current occurrence and rolls the series forward to the next —
        // the recurrence (and its OS alarm) stays live. The series only ends via Delete →
        // "Delete series". Centralised in `toggleMarkedDoneAdvancingRecurring` so the
        // inline-editor / row-while-editing toggle paths apply the same rule.
        var updated = take
        updated.toggleMarkedDoneAdvancingRecurring(now: Date())
        // In-place (owner 2026-06-27): mark-done greys just this row; a full reload+re-sort
        // is what made the swipe feel choppy. Done-ness doesn't change sort order (by
        // `createdAt`) or Obie membership, so an in-place update is faithful.
        saveInPlace(updated)
    }

    /// Take IDs with a pending snoozed re-nudge (owner 2026-06-21) — the timeline reads
    /// this to show "SNOOZED" instead of "OVERDUE" on those Takes' edges. Snooze is
    /// notification-only (no store write while locked), so this is refreshed from the OS
    /// pending queue when the app comes to the foreground; it can lag a lock-screen
    /// snooze until the next open, which is acceptable.
    private(set) var snoozedReminderIDs: Set<UUID> = []

    /// Refresh `snoozedReminderIDs` from the OS pending queue. No encryption key needed
    /// (it reads notifications, not the store), so it's safe even while locked.
    @MainActor
    func refreshSnoozedReminders() {
        Task { @MainActor in
            self.snoozedReminderIDs = await reminders.pendingSnoozedTakeIDs()
        }
    }

    /// Re-arm the rolling notification window for every repeating reminder (owner
    /// 2026-06-21). A recurring reminder is scheduled as a finite window of individual
    /// occurrences (so any one can be skipped); the window doesn't auto-extend, so we
    /// top it up whenever the app opens — keeping the next batch always pending. Reads
    /// the store directly (authoritative, includes the Obie); safe to call only once the
    /// store is unlocked. Best-effort: a load failure leaves existing alarms intact.
    /// Apply any reminder "Dismiss" taps made while the store was locked (owner 2026-06-22).
    /// Dismiss stops the CURRENT instance only: for a ONE-SHOT that means turning its alarm
    /// off (persisted here, now the key is available); for a RECURRING reminder it means
    /// leaving the series entirely alone, so future occurrences keep firing. The tap already
    /// cancelled the fired instance's OS alarm; the recurring window was never touched.
    ///
    /// MUST run BEFORE `refreshRecurringSchedules()` on unlock so a one-shot turned off here
    /// isn't re-armed by the rebuild. Saving cancels-and-reconciles the notification (a no-op
    /// re-schedule, since the alarm is now off) and reloads. No-op when the queue is empty;
    /// skips ids whose Take/reminder has gone, whose alarm is already off, or that REPEAT.
    func applyPendingReminderActions() {
        for action in PendingReminderActions.drainDismissed() {
            guard var updated = try? store.take(id: action.id) else { continue }
            if action.isLocation {
                // Dismiss on a PLACE reminder (2026-07-01): turn the geofence alarm
                // off — a geofence re-fires on every matching arrival/leave, so
                // "stop nagging" for a "where" means disabling it. Previously the
                // drain skipped location-only Takes entirely, so the unlock rebuild
                // re-armed the region and the reminder fired forever.
                guard updated.locationReminder?.alarmEnabled == true else { continue }
                updated.locationReminder?.alarmEnabled = false
            } else {
                guard let reminder = updated.timeReminder,
                      reminder.alarmEnabled,
                      !reminder.repeats else { continue }
                updated.timeReminder?.alarmEnabled = false
            }
            save(updated)
        }
    }

    /// Reconcile local notifications with a sync pass that changed local state
    /// (2026-07-01). Previously the remote-changes hook only reloaded the UI, so:
    /// a Take DELETED on another device kept its pending alarms here — at fire
    /// time the banner showed the deleted Take's decrypted title (a stale alarm
    /// AND a privacy leak for content the user deliberately removed) — and a
    /// reminder REMOVED remotely stayed armed. Cancels every id a deleted Take
    /// might own (incl. its delivered banners), reconciles applied edits, then
    /// reloads the snapshot.
    func applyRemoteChanges(_ report: SyncReport) {
        for id in report.deletedLocally {
            reminders.cancelReminder(identifier: id.uuidString)
        }
        for id in report.applied {
            guard let take = try? store.take(id: id) else { continue }
            reconcileNotification(for: take)
        }
        reload()
    }

    func refreshRecurringSchedules() {
        guard let all = try? store.allTakes() else { return }
        // Global rebuild (owner 2026-06-21): re-arms recurring windows AND keeps the whole
        // pending set within iOS's 64-alarm cap by favouring the soonest occurrences across
        // every reminder (one-shot + recurring). Pending snoozes are preserved.
        reminders.rescheduleAll(takes: all)
    }

    /// Roll a repeating reminder to its next occurrence — shared by "Done" (complete
    /// this one) and Delete → "Delete this occurrence" (skip this one). The series and
    /// its OS-repeating alarm are untouched; only the displayed next-due advances.
    func advanceRecurring(_ take: Take) {
        guard take.timeReminder?.repeats == true else { return }
        var updated = take
        // Advance past the occurrence currently shown, so the card visibly jumps to the
        // following one (the advance maths is single-sourced on the model).
        updated.advanceRecurringOccurrence(now: Date())
        save(updated)
    }

    // MARK: - Activity-type toggles (focus-ring fan applies these)

    /// Apply the focus-ring-fan selection to a Take, enforcing the Note floor.
    /// `reminderDate` is the time chosen in the Focus-ring's picker (owner
    /// 2026-06-17); falls back to any existing reminder time, then +24h.
    func applyActivityTypes(to take: Take,
                            isNote: Bool,
                            isTask: Bool,
                            hasReminder: Bool,
                            reminderDate: Date?,
                            reminderAlarm: Bool = true,
                            reminderAllDay: Bool = false,
                            reminderRecurrence: TimeReminder.Recurrence = .none,
                            reminderWeekdays: Set<Int> = [],
                            reminderLocation: LocationTrigger? = nil,
                            isImportant: Bool) {
        var updated = take
        updated.isNote = isNote
        updated.setTask(isTask)
        // Either/or (owner 2026-06-24): a location reminder takes precedence and clears the
        // time; otherwise the time "when" applies (when present).
        if let reminderLocation {
            updated.locationReminder = reminderLocation
            updated.timeReminder = nil
        } else {
            updated.locationReminder = nil
            if hasReminder {
                let when = reminderDate
                    ?? updated.timeReminder?.scheduledDate
                    ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                updated.timeReminder = TimeReminder(
                    scheduledDate: when,
                    notificationIdentifier: updated.id.uuidString,
                    alarmEnabled: reminderAlarm,
                    isAllDay: reminderAllDay,
                    recurrence: reminderRecurrence,
                    weekdays: reminderRecurrence == .weekly ? reminderWeekdays : []
                )
            } else {
                updated.timeReminder = nil
            }
        }
        updated.normaliseActivityFloor()

        // The Focus-ring's fourth Mark now toggles Important, not Obie (owner 2026-07-06).
        // Obie is left exactly as it was — the fan no longer designates or clears it (that
        // lives on the Iris long-press). An Obie always stays Important (model invariant),
        // so OR it in rather than letting a fan toggle strip the flag off a pinned Take.
        updated.isImportant = isImportant || updated.isObie
        save(updated)
    }

    // MARK: - Obie

    /// Long-press designates a Take as Obie. If one already exists and `replaceExisting`
    /// is false, the store throws `obieConflict` and we surface a confirmation need.
    func designateObie(_ take: Take, replaceExisting: Bool) {
        do {
            try store.setObie(id: take.id, replaceExisting: replaceExisting)
            reload()
            notifyLocalChange()
        } catch StorageError.obieConflict(let existing) {
            pendingObieConflict = (newTake: take.id, existing: existing)
        } catch {
            lastError = "Couldn't set Obie."
        }
    }

    /// Long-press on an Obie's Iris turns it back into a standard Take (owner
    /// 2026-07-04). Mirrors the Focus-ring "Obie off" path: clear the flag and
    /// re-save — `upsert` re-seals the payload and clears the isObie column, and
    /// `save` reloads + notifies. NOT entitlement-gated: removing a designation is
    /// always allowed, even on a lapsed trial. (The auto-set Important flag is left
    /// as-is, matching the Focus-ring demote.)
    func demoteObie(_ take: Take) {
        var t = take
        t.isObie = false
        save(t)
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
            notifyLocalChange()
        } catch {
            lastError = "Couldn't set Obie."
        }
    }

    func cancelObieReplacement() { pendingObieConflict = nil }
}
