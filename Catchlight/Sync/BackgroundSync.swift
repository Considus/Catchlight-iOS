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

    /// Invoked on the main actor with the conflicts surfaced by each sync pass, so
    /// the UI layer can enqueue them for resolution (Task 6.15). Optional — the
    /// coordinator continues to work for background-only callers that don't have
    /// (or want) a conflict queue.
    private let onConflicts: (@MainActor ([(local: Take, remote: Take)]) -> Void)?

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

    /// Invoked on the main actor after a sync pass that CHANGED local state
    /// (applied remote versions or applied remote deletions), so the UI layer
    /// can reload its view-model snapshots. Foreground-sync support
    /// (2026-06-10); nil for callers that don't render.
    private let onRemoteChanges: (@MainActor (SyncReport) -> Void)?

    /// - Parameter makeEngine: builds a SyncEngine if a cloud folder is configured
    ///   and the master key is available; returns nil in local-only/locked states.
    /// - Parameter onConflicts: hand-off for conflicts detected during the sync.
    ///   Called on `MainActor`; pass `nil` for callers that don't surface conflicts.
    /// - Parameter onSyncError: hand-off for thrown sync errors (Task 3.9).
    /// - Parameter onQuarantined: hand-off for per-blob quarantine ids (Task 3.9).
    public init(makeEngine: @escaping () -> SyncEngine?,
                onConflicts: (@MainActor ([(local: Take, remote: Take)]) -> Void)? = nil,
                onSyncError: (@MainActor (Error) -> Void)? = nil,
                onQuarantined: (@MainActor ([UUID]) -> Void)? = nil,
                onRemoteChanges: (@MainActor (SyncReport) -> Void)? = nil) {
        self.makeEngine = makeEngine
        self.onConflicts = onConflicts
        self.onSyncError = onSyncError
        self.onQuarantined = onQuarantined
        self.onRemoteChanges = onRemoteChanges
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
        guard SettingsViewModel.SyncMode.current == .auto else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Surfacing this matters: a silently-swallowed submit error (e.g. an
            // Info.plist identifier mismatch) is the classic "background sync
            // never runs and nobody can tell why" failure.
            Self.logger.error("BGTaskScheduler.submit failed: \(String(describing: error))")
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
    }

    /// Minimum spacing between consecutive `appBecameActive` syncs.
    public static let autoSyncMinimumInterval: TimeInterval = 60

    private let stateLock = NSLock()
    private var isSyncing = false
    private var lastActivationSync: Date?

    /// Pure throttle decision — extracted for unit testing.
    static func shouldRunActivationSync(lastRun: Date?, now: Date,
                                        minimumInterval: TimeInterval) -> Bool {
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= minimumInterval
    }

    /// Run a sync pass now, off the main thread, reusing the session's
    /// in-memory keys (via `makeEngine`). Single-flight: a trigger arriving
    /// while a pass is in flight is dropped (the running pass already covers
    /// it; sync is idempotent). Call from the main thread.
    public func syncNow(trigger: ForegroundSyncTrigger, now: Date = Date()) {
        // Sync-mode gate (owner 2026-06-21). `disabled` blocks everything;
        // `manual` blocks every automatic trigger and lets only the explicit
        // "Sync Now" tap through. `auto` is unchanged.
        switch SettingsViewModel.SyncMode.current {
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
        guard !isSyncing else { stateLock.unlock(); return }
        isSyncing = true
        stateLock.unlock()

        guard let engine = makeEngine() else {
            stateLock.lock(); isSyncing = false; stateLock.unlock()
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
            if let self {
                self.stateLock.lock(); self.isSyncing = false; self.stateLock.unlock()
            }
            DispatchQueue.main.async {
                if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion) }
            }
        }

        let onConflicts = self.onConflicts
        let onSyncError = self.onSyncError
        let onQuarantined = self.onQuarantined
        let onRemoteChanges = self.onRemoteChanges

        DispatchQueue.global(qos: .utility).async {
            defer { finish() }
            do {
                let report = try engine.sync(isCancelled: { cancel.isCancelled })
                Self.deliver(report,
                             onConflicts: onConflicts,
                             onQuarantined: onQuarantined,
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

    /// Shared report fan-out for both the BGTask and foreground paths.
    private static func deliver(_ report: SyncReport,
                                onConflicts: (@MainActor ([(local: Take, remote: Take)]) -> Void)?,
                                onQuarantined: (@MainActor ([UUID]) -> Void)?,
                                onRemoteChanges: (@MainActor (SyncReport) -> Void)?) {
        if let onConflicts, !report.conflicts.isEmpty {
            let conflicts = report.conflicts
            Task { @MainActor in onConflicts(conflicts) }
        }
        if let onQuarantined, !report.quarantined.isEmpty {
            let quarantined = report.quarantined
            Task { @MainActor in onQuarantined(quarantined) }
        }
        // Long-offline hold-back (2026-07-01): push declined to self-heal-upload
        // Takes this device hasn't touched since before the tombstone-retention
        // window (they may have been deleted fleet-wide in the interim). Surface
        // a content-free count in Notice History — the user re-asserts a Take by
        // editing it. DiagnosticsLog is thread-safe; no main-actor hop needed.
        if !report.heldBack.isEmpty {
            let n = report.heldBack.count
            DiagnosticsLog.shared.record(.sync,
                "\(n) Take\(n == 1 ? "" : "s") not re-uploaded — this device was away too long "
                + "to rule out deletion elsewhere. Edit a Take to sync it again.")
        }
        if let onRemoteChanges, !report.applied.isEmpty || !report.deletedLocally.isEmpty {
            Task { @MainActor in onRemoteChanges(report) }
        }
    }

    private func handle(task: BGAppRefreshTask) {
        // A pass scheduled while in `.auto` can still fire after the user switches
        // to Manual/Disabled — honour the current mode and bail without resyncing
        // or rescheduling (owner 2026-06-21).
        guard SettingsViewModel.SyncMode.current == .auto else {
            task.setTaskCompleted(success: true); return
        }
        scheduleNext()   // always reschedule (auto-only, guarded above)

        let onConflicts = self.onConflicts
        let onSyncError = self.onSyncError
        let onQuarantined = self.onQuarantined
        let onRemoteChanges = self.onRemoteChanges
        let makeEngine = self.makeEngine
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
                    let report = try engine.sync(isCancelled: { cancel.isCancelled })
                    Self.deliver(report,
                                 onConflicts: onConflicts,
                                 onQuarantined: onQuarantined,
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
