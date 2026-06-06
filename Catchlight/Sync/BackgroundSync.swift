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

    /// Schedule the next refresh. Call on every foreground → background transition.
    public func scheduleNext(earliestInterval: TimeInterval = 15 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(task: BGAppRefreshTask) {
        scheduleNext()   // always reschedule

        guard let engine = makeEngine() else { task.setTaskCompleted(success: true); return }

        let onConflicts = self.onConflicts
        let onSyncError = self.onSyncError
        let onQuarantined = self.onQuarantined
        let work = DispatchWorkItem {
            do {
                let report = try engine.sync()   // pull + push; idempotent
                if let onConflicts, !report.conflicts.isEmpty {
                    let conflicts = report.conflicts
                    Task { @MainActor in onConflicts(conflicts) }
                }
                if let onQuarantined, !report.quarantined.isEmpty {
                    let quarantined = report.quarantined
                    Task { @MainActor in onQuarantined(quarantined) }
                }
                task.setTaskCompleted(success: true)
            } catch {
                if let onSyncError {
                    Task { @MainActor in onSyncError(error) }
                }
                task.setTaskCompleted(success: false)
            }
        }
        task.expirationHandler = { work.cancel() }
        DispatchQueue.global(qos: .background).async(execute: work)
    }
}
