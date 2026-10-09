//
//  BackgroundSync.swift
//  Catchlight (iOS app target)
//
//  Background sync scheduling (Phase 5 brief §7.8) and second-device handshake
//  polling (Encryption Architecture §6 step 4). Uses BGTaskScheduler with the
//  identifier registered in Info.plist (`com.considus.catchlight.sync`).
//
//  iOS does not guarantee background-execution timing, so the SyncEngine is
//  idempotent — running it repeatedly with the same state is safe.
//
//  Task 3.9: Error and edge-case states — the coordinator now reports both
//  thrown errors and per-blob quarantines back to the main actor so the UI can
//  surface non-blocking notice strips.
//

import Foundation
import BackgroundTasks
import UIKit
import CatchlightCore
import os

public final class BackgroundSyncCoordinator {

    public static let taskIdentifier = "com.considus.catchlight.sync"

    private let makeEngine: () -> SyncEngine?

    /// The Takes waiting for the user's conflict choice (`ConflictQueue.held`). Every pass
    /// holds them: never uploaded, never overwritten or deleted from the folder's side, until
    /// the user chooses (owner 2026-10-07). nil for a caller with no queue.
    private let heldTakes: HeldTakes?

    /// Invoked on the main actor with the conflicts surfaced by each sync pass, so
    /// the UI layer can enqueue them for resolution (Task 6.15). Optional — the
    /// coordinator continues to work for background-only callers that don't have
    /// (or want) a conflict queue.
    private let onConflicts: (@MainActor ([(local: Take, remote: Take)]) -> Void)?
    /// Cloud copies that failed verification and need the user (2026-09-30).
    private let onUnverified: (@MainActor ([UnverifiedCopy]) -> Void)?

    /// Invoked on the main actor when `SyncEngine.sync()` throws (Task 3.9). The
    /// caller maps the error to a friendly string and surfaces a non-blocking
    /// strip on the timeline. The expected "local-only mode" case
    /// (`SyncError.noCloudFolderConfigured`) is still forwarded — filtering is
    /// the caller's concern.
    private let onSyncError: (@MainActor (Error) -> Void)?

    /// Invoked on the main actor with the per-blob quarantined Take ids surfaced
    /// by each pull pass (Task 3.9). The caller increments a count for display;
    /// the UI never exposes the UUIDs themselves.
    private let onQuarantined: (@MainActor ([UUID]) -> Void)?

    /// Invoked on the main actor with the number of Takes a push held back because this
    /// device was away too long to rule out deletion elsewhere (shown in the sync strip).
    private let onHeldBack: (@MainActor (Int) -> Void)?

    /// Invoked on the main actor after a sync pass that CHANGED local state
    /// (applied remote versions or applied remote deletions), so the UI layer
    /// can reload its view-model snapshots. Foreground-sync support
    /// (2026-06-10); nil for callers that don't render.
    private let onRemoteChanges: (@MainActor (SyncReport) -> Void)?

    /// Invoked on the main actor with the Takes a pass let go of (`SyncReport.deletedLocally`),
    /// for the conflict queue to drop pairs that no longer have a Take on this device.
    private let onReleased: (@MainActor ([UUID]) -> Void)?

    /// Invoked on the main actor with the held Takes whose other side another device has turned
    /// into a Script (`SyncReport.heldConverted`), for the conflict queue to mark them. Delivered
    /// after the pass's conflicts, so a pair queued in the same pass is there to mark.
    private let onHeldConverted: (@MainActor ([UUID]) -> Void)?

    /// - Parameter makeEngine: builds a SyncEngine if a cloud folder is configured
    ///   and the master key is available; returns nil in local-only/locked states.
    /// - Parameter onConflicts: hand-off for conflicts detected during the sync.
    ///   Called on `MainActor`; pass `nil` for callers that don't surface conflicts.
    /// - Parameter onSyncError: hand-off for thrown sync errors (Task 3.9).
    /// - Parameter onQuarantined: hand-off for per-blob quarantine ids (Task 3.9).
    /// - Parameter onHeldBack: hand-off for the count of Takes a push held back.
    /// - Parameter heldTakes: the conflict queue's held Takes, read at the start of each pass.
    init(makeEngine: @escaping () -> SyncEngine?,
                heldTakes: HeldTakes? = nil,
                onConflicts: (@MainActor ([(local: Take, remote: Take)]) -> Void)? = nil,
                onUnverified: (@MainActor ([UnverifiedCopy]) -> Void)? = nil,
                onSyncError: (@MainActor (Error) -> Void)? = nil,
                onQuarantined: (@MainActor ([UUID]) -> Void)? = nil,
                onHeldBack: (@MainActor (Int) -> Void)? = nil,
                onRemoteChanges: (@MainActor (SyncReport) -> Void)? = nil,
                onReleased: (@MainActor ([UUID]) -> Void)? = nil,
                onHeldConverted: (@MainActor ([UUID]) -> Void)? = nil) {
        self.makeEngine = makeEngine
        self.heldTakes = heldTakes
        self.onConflicts = onConflicts
        self.onUnverified = onUnverified
        self.onSyncError = onSyncError
        self.onQuarantined = onQuarantined
        self.onHeldBack = onHeldBack
        self.onRemoteChanges = onRemoteChanges
        self.onReleased = onReleased
        self.onHeldConverted = onHeldConverted
    }

    /// Call once at launch (before app finishes launching).
    public func registerLaunchHandler() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handle(task: task as! BGAppRefreshTask)
        }
    }

    private static let logger = Logger(subsystem: "com.considus.catchlight", category: "background-sync")

    /// Schedule the next refresh. Call on every foreground → background transition.
    /// No-op outside `.auto` (owner 2026-06-21): Manual and Disabled never run a
    /// background pass, so don't claim a background-refresh slot for one.
    public func scheduleNext(earliestInterval: TimeInterval = 15 * 60) {
        guard SettingsViewModel.SyncMode.current() == .auto else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Surfacing this matters: a silently-swallowed submit error (e.g. an
            // Info.plist identifier mismatch) is the classic "background sync
            // never runs and nobody can tell why" failure.
            Self.logger.error("BGTaskScheduler.submit failed: \(String(describing: error))")
            // ALSO into the exportable log (owner 2026-07-16): os.Logger can't be pulled from a
            // user's device, so this — the comment above literally calls it "the classic
            // 'background sync never runs and nobody can tell why' failure" — was invisible in
            // exactly the case it describes. Content-free: system error domain/code only.
            let ns = error as NSError
            DiagnosticsLog.shared.record(.backgroundSyncNotScheduled(domain: ns.domain, code: ns.code))
        }
    }

    /// One-shot completion guard. Apple's BGTask contract requires
    /// `setTaskCompleted` to be called EXACTLY ONCE on every path — including
    /// expiration. The previous implementation cancelled a not-yet-started work
    /// item on expiry, after which nothing ever completed the task (an API
    /// contract violation that deprioritises future background allotment).
    private final class TaskCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func complete(_ task: BGAppRefreshTask, success: Bool) {
            lock.lock(); defer { lock.unlock() }
            guard !done else { return }
            done = true
            task.setTaskCompleted(success: success)
        }
    }

    /// Cooperative cancellation flag checked by the sync engine between items.
    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func cancel() { lock.lock(); value = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    // MARK: - Foreground sync (2026-06-10)
    //
    // The master key carries `.userPresence`, so a cold BGAppRefreshTask on
    // hardware can never unwrap it — background refresh is a best-effort
    // bonus, not the primary sync path. These triggers run sync while the
    // session keys are already in memory (no prompt):
    //   • app became active   (throttled — `.inactive → .active` flips happen
    //     for Face ID sheets, Notification Centre, the app switcher…)
    //   • app entering background (un-throttled — pushes the session's edits
    //     out under a UIKit background-task assertion before suspension)

    public enum ForegroundSyncTrigger {
        case appBecameActive
        case appEnteringBackground
        /// Explicit "Sync Now" tap from Cloud Storage (owner 2026-06-21). The ONLY
        /// trigger that still fires when SyncMode is `.manual`.
        case manualButton
        /// A local Take edit was committed (owner 2026-07-02). Debounced via
        /// `syncAfterSave()`; an automatic trigger, so `.manual` mode still blocks it.
        case saveCommitted
    }

    /// Minimum spacing between consecutive `appBecameActive` syncs.
    public static let autoSyncMinimumInterval: TimeInterval = 60
    /// Coalescing delay for sync-on-save: rapid edits within this window fold into one
    /// push (owner 2026-07-02).
    public static let saveDebounceInterval: TimeInterval = 2

    private let stateLock = NSLock()
    private let flight = SyncFlight()
    private var lastActivationSync: Date?
    /// Pending debounced save-sync, cancelled + rescheduled on each new save.
    private var saveDebounce: DispatchWorkItem?

    /// Push local edits shortly after they're saved (owner 2026-07-02): a change is
    /// safest once it's on the cloud, and it makes multi-device feel live. Debounced so
    /// a burst of edits coalesces into one push; a no-op outside `.auto` (also gated in
    /// `syncNow`). Call from the main thread.
    public func syncAfterSave() {
        guard SettingsViewModel.SyncMode.current() == .auto else { return }
        saveDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.syncNow(trigger: .saveCommitted) }
        saveDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDebounceInterval, execute: work)
    }

    /// Pure throttle decision — extracted for unit testing.
    static func shouldRunActivationSync(lastRun: Date?, now: Date,
                                        minimumInterval: TimeInterval) -> Bool {
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= minimumInterval
    }

    /// Run a sync pass now, off the main thread, reusing the session's
    /// in-memory keys (via `makeEngine`). Single-flight: a trigger arriving
    /// while a pass is in flight runs once more after it (`SyncFlight`), because the
    /// running pass may already be past what the trigger is about: a conflict choice made
    /// mid-pass, for one. Call from the main thread.
    public func syncNow(trigger: ForegroundSyncTrigger, now: Date = Date()) {
        // Sync-mode gate (owner 2026-06-21). `disabled` blocks everything;
        // `manual` blocks every automatic trigger and lets only the explicit
        // "Sync Now" tap through. `auto` is unchanged.
        switch SettingsViewModel.SyncMode.current() {
        case .disabled:
            return
        case .manual where trigger != .manualButton:
            return
        case .manual, .auto:
            break
        }

        stateLock.lock()
        if trigger == .appBecameActive,
           !Self.shouldRunActivationSync(lastRun: lastActivationSync, now: now,
                                         minimumInterval: Self.autoSyncMinimumInterval) {
            stateLock.unlock()
            return
        }
        stateLock.unlock()
        guard flight.begin(trigger) else { return }

        guard let engine = makeEngine() else {
            _ = flight.end()
            return   // local-only mode, locked, or pre-onboarding — nothing to do
        }

        // Stamp the activation throttle ONLY now that a sync is actually proceeding
        // (the engine built) — NOT before the `makeEngine` guard (2026-07-02). On a
        // cold launch the first `.appBecameActive` fires while still LOCKED, so it
        // bails at `makeEngine` (keys not cached); stamping beforehand made the
        // post-unlock `.appBecameActive` (fired seconds later) throttle out, so a cold
        // launch never synced until a manual tap or a >60s-later foreground.
        if trigger == .appBecameActive {
            stateLock.lock(); lastActivationSync = now; stateLock.unlock()
        }

        // Background-task assertion: the entering-background trigger must be
        // allowed to finish its (short, idempotent) pass after suspension
        // starts. The engine is crash-safe regardless — an interrupted push
        // self-heals on the next pass.
        var assertion: UIBackgroundTaskIdentifier = .invalid
        let cancel = CancelFlag()
        assertion = UIApplication.shared.beginBackgroundTask(withName: "catchlight.foreground-sync") {
            cancel.cancel()
        }
        let finish: () -> Void = { [weak self] in
            let rerun = self?.flight.end()
            DispatchQueue.main.async {
                if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion) }
                if let rerun { self?.syncNow(trigger: rerun) }
            }
        }

        let onConflicts = self.onConflicts
        let onUnverified = self.onUnverified
        let onSyncError = self.onSyncError
        let onQuarantined = self.onQuarantined
        let onHeldBack = self.onHeldBack
        let onRemoteChanges = self.onRemoteChanges
        let onReleased = self.onReleased
        let onHeldConverted = self.onHeldConverted
        let heldTakes = self.heldTakes

        DispatchQueue.global(qos: .utility).async {
            defer { finish() }
            do {
                let (report, generation) = try Self.pass(engine, holding: heldTakes,
                                                         isCancelled: { cancel.isCancelled })
                Self.deliver(report, heldTakes: heldTakes, generation: generation,
                             onReleased: onReleased,
                             onHeldConverted: onHeldConverted,
                             onConflicts: onConflicts,
                             onUnverified: onUnverified,
                             onQuarantined: onQuarantined,
                             onHeldBack: onHeldBack,
                             onRemoteChanges: onRemoteChanges)
            } catch is CancellationError {
                // Assertion expired mid-pass; the next trigger resumes cleanly.
            } catch {
                if let onSyncError {
                    Task { @MainActor in onSyncError(error) }
                }
            }
        }
    }

    /// One sync pass, shared by the foreground and BGTask paths: the Takes waiting for a
    /// conflict choice are read as the pass starts, so a conflict queued by the previous pass
    /// is already held.
    /// Returns the queue generation the pass started in, for `deliver` to check.
    @discardableResult
    static func pass(_ engine: SyncEngine, holding heldTakes: HeldTakes?,
                     isCancelled: () -> Bool) throws -> (report: SyncReport, generation: Int?) {
        let snapshot = heldTakes?.snapshot
        let report = try engine.sync(isCancelled: isCancelled, holding: snapshot?.ids ?? [])
        return (report, snapshot?.generation)
    }

    /// Whether a pass begun in `generation` may still deliver into the conflict queue: not if
    /// the queue was detached or re-attached meanwhile (relock, Start over, Second device), when
    /// its pairs belong to a session or an account that has gone.
    static func isCurrent(_ generation: Int?, _ heldTakes: HeldTakes?) -> Bool {
        heldTakes?.generation == generation
    }

    /// Shared report fan-out for both the BGTask and foreground paths.
    private static func deliver(_ report: SyncReport,
                                heldTakes: HeldTakes?, generation: Int?,
                                onReleased: (@MainActor ([UUID]) -> Void)?,
                                onHeldConverted: (@MainActor ([UUID]) -> Void)?,
                                onConflicts: (@MainActor ([(local: Take, remote: Take)]) -> Void)?,
                                onUnverified: (@MainActor ([UnverifiedCopy]) -> Void)?,
                                onQuarantined: (@MainActor ([UUID]) -> Void)?,
                                onHeldBack: (@MainActor (Int) -> Void)?,
                                onRemoteChanges: (@MainActor (SyncReport) -> Void)?) {
        // Into the conflict queue only if it is still the queue this pass started with.
        if let onReleased, !report.deletedLocally.isEmpty {
            let released = report.deletedLocally
            Task { @MainActor in if isCurrent(generation, heldTakes) { onReleased(released) } }
        }
        // One hop for both, conflicts first, so a pair queued by this pass is there to be marked.
        if !report.conflicts.isEmpty || !report.heldConverted.isEmpty, onConflicts != nil || onHeldConverted != nil {
            let conflicts = report.conflicts, converted = report.heldConverted
            Task { @MainActor in
                guard isCurrent(generation, heldTakes) else { return }
                if !conflicts.isEmpty { onConflicts?(conflicts) }
                if !converted.isEmpty { onHeldConverted?(converted) }
            }
        }
        if let onUnverified, !report.unverified.isEmpty {
            let unverified = report.unverified
            Task { @MainActor in if isCurrent(generation, heldTakes) { onUnverified(unverified) } }
        }
        if let onQuarantined, !report.quarantined.isEmpty {
            let quarantined = report.quarantined
            Task { @MainActor in onQuarantined(quarantined) }
        }
        // Long-offline hold-back (2026-07-01): push declined to self-heal-upload
        // Takes this device hasn't touched since before the tombstone-retention
        // window (they may have been deleted fleet-wide in the interim). The count shows
        // in the sync strip (owner 2026-10-04) and so in Notice History; the user re-asserts
        // a Take by editing it. A caller with no strip still gets the log line.
        if !report.heldBack.isEmpty {
            let n = report.heldBack.count
            if let onHeldBack {
                Task { @MainActor in onHeldBack(n) }
            } else {
                DiagnosticsLog.shared.record(.takesHeldBack(n))
            }
        }
        if let onRemoteChanges, !report.applied.isEmpty || !report.deletedLocally.isEmpty {
            Task { @MainActor in onRemoteChanges(report) }
        }
    }

    private func handle(task: BGAppRefreshTask) {
        // A pass scheduled while in `.auto` can still fire after the user switches
        // to Manual/Disabled — honour the current mode and bail without resyncing
        // or rescheduling (owner 2026-06-21).
        guard SettingsViewModel.SyncMode.current() == .auto else {
            task.setTaskCompleted(success: true); return
        }
        scheduleNext()   // always reschedule (auto-only, guarded above)

        let onConflicts = self.onConflicts
        let onUnverified = self.onUnverified
        let onSyncError = self.onSyncError
        let onQuarantined = self.onQuarantined
        let onHeldBack = self.onHeldBack
        let onRemoteChanges = self.onRemoteChanges
        let makeEngine = self.makeEngine
        let heldTakes = self.heldTakes
        let onReleased = self.onReleased
        let onHeldConverted = self.onHeldConverted
        let completion = TaskCompletion()
        let cancel = CancelFlag()

        task.expirationHandler = {
            // Ask the in-flight sync to stop at the next item boundary, and
            // complete the task NOW — whether or not the work ever started.
            cancel.cancel()
            completion.complete(task, success: false)
        }

        // Engine construction hops to MAIN (2026-07-01): `makeEngine` reads
        // Wiring's main-confined `sessionKeys` — a struct, so reading it from
        // BGTaskScheduler's background queue concurrently with `relock()`
        // clearing it on main (which fires on `protectedDataWillBecomeUnavailable`,
        // exactly when a background refresh may be in flight) was a torn-read
        // race, not mere staleness. The sync itself still runs off-main.
        DispatchQueue.main.async {
            guard let engine = makeEngine() else {
                completion.complete(task, success: true)
                return
            }
            DispatchQueue.global(qos: .background).async {
                do {
                    // pull + push; idempotent. Checks `cancel` between items so an
                    // expiring task lets go of cloud-file access promptly instead of
                    // running on past expiry (a 0xdead10cc termination risk).
                    let (report, generation) = try Self.pass(engine, holding: heldTakes,
                                                             isCancelled: { cancel.isCancelled })
                    Self.deliver(report, heldTakes: heldTakes, generation: generation,
                                 onReleased: onReleased,
                                 onHeldConverted: onHeldConverted,
                                 onConflicts: onConflicts,
                                 onUnverified: onUnverified,
                                 onQuarantined: onQuarantined,
                                 onHeldBack: onHeldBack,
                                 onRemoteChanges: onRemoteChanges)
                    completion.complete(task, success: true)
                } catch is CancellationError {
                    // Expiration already completed the task.
                } catch {
                    if let onSyncError {
                        Task { @MainActor in onSyncError(error) }
                    }
                    completion.complete(task, success: false)
                }
            }
        }
    }
}

/// Single-flight for foreground sync. One pass at a time; a trigger that arrives while one is
/// running is not dropped but remembered, and `end()` hands it back so the caller runs one more
/// pass. Several triggers during one pass collapse into a single rerun. An activation trigger
/// is never remembered: the running pass already does what it asks.
final class SyncFlight: @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private var pending: BackgroundSyncCoordinator.ForegroundSyncTrigger?

    /// True if the caller should run a pass now.
    func begin(_ trigger: BackgroundSyncCoordinator.ForegroundSyncTrigger) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard running else { running = true; return true }
        // A manual tap outranks an automatic trigger: in Manual mode only it may run.
        if trigger != .appBecameActive, pending != .manualButton { pending = trigger }
        return false
    }

    /// The pass is over. Returns a trigger to run again, if one arrived meanwhile.
    func end() -> BackgroundSyncCoordinator.ForegroundSyncTrigger? {
        lock.lock(); defer { lock.unlock() }
        running = false
        defer { pending = nil }
        return pending
    }
}
