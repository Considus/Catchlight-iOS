//
//  AppModel.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  The application-scope model: holds the shared UIState and the feature view
//  models, and decides onboarding vs. main app. Built once by Wiring at launch and
//  injected into the environment. @Observable (iOS 17+).
//
//  It does NOT construct the SQLCipher store itself — that requires the Keychain
//  master key, which only exists after onboarding. The store is supplied (post-
//  onboarding) by Wiring, so AppModel stays free of platform crypto wiring and is
//  trivially previewable with an InMemoryTakeStore.
//

// Task 3.9: Error and edge-case states — adds `lastSyncError` and `quarantinedCount`
// for the non-blocking sync error / quarantine notice strips on the timeline.

import SwiftUI
import Observation
import CatchlightCore

@Observable
@MainActor
final class AppModel {

    let ui = UIState()
    /// First-run orientation state (Task 3.13). Tracks which of the four one-time
    /// hints is currently active; persisted in UserDefaults so each is shown once.
    let orientation = FirstRunOrientationState()
    /// Pending sync conflicts surfaced by BackgroundSync (Task 6.15). Drives the
    /// amber banner on the timeline and the resolution sheet. In-memory only —
    /// conflicts re-detect on the next sync if dismissed without resolving.
    let conflictQueue = ConflictQueue()

    /// User-readable summary of the most recent sync failure (Task 3.9). Drives
    /// the non-blocking ruby error strip in `DailiesView`. nil = no current error.
    /// Set by BackgroundSync via `reportSyncError(_:)`; cleared by the strip's
    /// Dismiss button or its 8-second auto-dismiss timer.
    var lastSyncError: String?

    /// Number of Takes the last sync pass refused to decrypt because their
    /// per-blob HMAC didn't verify (Task 3.9). UUIDs are deliberately NOT exposed
    /// to the UI — privacy. Drives a second non-blocking strip when > 0; tapping
    /// Dismiss in the view resets to zero.
    var quarantinedCount: Int = 0

    private(set) var needsOnboarding: Bool
    private(set) var onboardingVM: OnboardingViewModel?

    // Feature view models. Available once a store is bound (after onboarding).
    private(set) var dailiesVM: DailiesViewModel
    private(set) var searchVM: SearchViewModel
    private(set) var sequenceVM: SequenceViewModel

    /// Supplies the production store after the master key exists. Injected by Wiring.
    private let storeProvider: () -> TakeStore?

    init(needsOnboarding: Bool,
         initialStore: TakeStore,
         storeProvider: @escaping () -> TakeStore?) {
        self.needsOnboarding = needsOnboarding
        self.storeProvider = storeProvider
        self.dailiesVM = DailiesViewModel(store: initialStore)
        self.searchVM = SearchViewModel(store: initialStore)
        self.sequenceVM = SequenceViewModel(store: initialStore)

        if needsOnboarding {
            self.onboardingVM = nil
            self.onboardingVM = OnboardingViewModel { [weak self] in
                self?.completeOnboarding()
            }
        }
    }

    /// Called by OnboardingViewModel after the master key is stored. Rebinds the
    /// feature view models to the now-openable production store and seeds the first
    /// Takes, then flips to the main app.
    private func completeOnboarding() {
        if let store = storeProvider() {
            seedIfEmpty(store)
            rebind(to: store)
        }
        onboardingVM = nil
        needsOnboarding = false
    }

    private func seedIfEmpty(_ store: TakeStore) {
        if (try? store.allTakes())?.isEmpty ?? true {
            for take in SeedTakes.make() { try? store.upsert(take) }
        }
    }

    private func rebind(to store: TakeStore) {
        dailiesVM = DailiesViewModel(store: store)
        searchVM = SearchViewModel(store: store)
        sequenceVM = SequenceViewModel(store: store)
    }

    // MARK: - Task 3.9 — sync error & quarantine reporting

    /// Map a raw error from `BackgroundSyncCoordinator` to the friendly string
    /// shown in the timeline strip, or `nil` if the error is the expected
    /// "local-only mode" case and should NOT be surfaced. Pure / static so the
    /// mapping can be unit-tested without spinning up the whole AppModel.
    static func friendlySyncErrorMessage(for error: Error) -> String? {
        if let sync = error as? SyncError {
            switch sync {
            case .manifestSignatureInvalid:
                return "Sync paused — your cloud data looks unexpected. No changes were made locally."
            case .noCloudFolderConfigured:
                // Expected in local-only mode — never surface to the user.
                return nil
            default:
                return "Sync encountered a problem and will retry."
            }
        }
        if let lock = error as? SyncLockError {
            switch lock {
            case .heldByOtherDevice:
                return "Another device is syncing. Catchlight will retry automatically."
            default:
                return "Sync encountered a problem and will retry."
            }
        }
        return "Sync encountered a problem and will retry."
    }

    /// Record a sync failure for display. Filters out the `noCloudFolderConfigured`
    /// case (local-only is not an error).
    func reportSyncError(_ error: Error) {
        if let message = Self.friendlySyncErrorMessage(for: error) {
            lastSyncError = message
        }
    }

    /// Add to the running quarantine count from the latest sync pass.
    func reportQuarantined(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        quarantinedCount += ids.count
    }

    /// Strip-side actions — clear the matching state.
    func clearSyncError() { lastSyncError = nil }
    func clearQuarantineNotice() { quarantinedCount = 0 }

    // MARK: - Previews

    static func preview(store: TakeStore, onboarded: Bool) -> AppModel {
        AppModel(
            needsOnboarding: !onboarded,
            initialStore: store,
            storeProvider: { store }
        )
    }
}
