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

    /// - Parameter makeEngine: builds a SyncEngine if a cloud folder is configured
    ///   and the master key is available; returns nil in local-only/locked states.
    /// - Parameter onConflicts: hand-off for conflicts detected during the sync.
    ///   Called on `MainActor`; pass `nil` for callers that don't surface conflicts.
    /// - Parameter onSyncError: hand-off for thrown sync errors (Task 3.9).
    /// - Parameter onQuarantined: hand-off for per-blob quarantine ids (Task 3.9).
    public init(makeEngine: @escaping () -> SyncEngine?,
                onConflicts: (@MainActor ([(local: Take, remote: Take)]) -> Void)? = nil,
                onSyncError: (@MainActor (Error) -> Void)? = nil,
                onQuarantined: (@MainActor ([UUID]) -> Void)? = nil) {
        self.makeEngine = makeEngine
        self.onConflicts = onConflicts
        self.onSyncError = onSyncError
        self.onQuarantined = onQuarantined
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
    public func scheduleNext(earliestInterval: TimeInterval = 15 * 60) {
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

    private func handle(task: BGAppRefreshTask) {
        scheduleNext()   // always reschedule

        guard let engine = makeEngine() else { task.setTaskCompleted(success: true); return }

        let onConflicts = self.onConflicts
        let onSyncError = self.onSyncError
        let onQuarantined = self.onQuarantined
        let completion = TaskCompletion()
        let cancel = CancelFlag()

        task.expirationHandler = {
            // Ask the in-flight sync to stop at the next item boundary, and
            // complete the task NOW — whether or not the work ever started.
            cancel.cancel()
            completion.complete(task, success: false)
        }

        DispatchQueue.global(qos: .background).async {
            do {
                // pull + push; idempotent. Checks `cancel` between items so an
                // expiring task lets go of cloud-file access promptly instead of
                // running on past expiry (a 0xdead10cc termination risk).
                let report = try engine.sync(isCancelled: { cancel.isCancelled })
                if let onConflicts, !report.conflicts.isEmpty {
                    let conflicts = report.conflicts
                    Task { @MainActor in onConflicts(conflicts) }
                }
                if let onQuarantined, !report.quarantined.isEmpty {
                    let quarantined = report.quarantined
                    Task { @MainActor in onQuarantined(quarantined) }
                }
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
