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

    /// Subscription manager (Tasks 6.20 / 6.21). Owns StoreKit access and
    /// exposes the current `SubscriptionStatus` to the UI. Constructed by
    /// Wiring so previews can inject a stand-in that reports any state.
    let subscription: SubscriptionManager

    /// Convenience: the current entitlement state. Mirrors `subscription.status`
    /// so views can read a single ergonomic property.
    var subscriptionStatus: SubscriptionStatus { subscription.status }

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

    // Feature view model. Available once a store is bound (after onboarding).
    // (Dock redesign 2026-06-10: the timeline is the ONE surface; the former
    // Search/Sequence view models are gone — the dock's live filter narrows
    // the Dailies snapshot directly via SequenceFilter.)
    private(set) var dailiesVM: DailiesViewModel

    /// Supplies the production store after the master key exists. Injected by Wiring.
    private let storeProvider: () -> TakeStore?

    /// Task 6.19 — Spotlight indexer. Held here so the same instance is shared
    /// across the lifetime of the app: DailiesViewModel uses it on save/delete,
    /// SubscriptionManager uses it to deindex everything on lapse.
    let spotlight: SpotlightIndexing

    // `subscription` has no default value: SubscriptionManager.init is
    // @MainActor-isolated and a default argument evaluates in a nonisolated
    // context (compile error under the current toolchain). Callers construct it
    // explicitly (Wiring does; previews use `AppModel.preview`).
    init(needsOnboarding: Bool,
         initialStore: TakeStore,
         storeProvider: @escaping () -> TakeStore?,
         subscription: SubscriptionManager,
         spotlight: SpotlightIndexing = NoopSpotlightIndexer()) {
        self.needsOnboarding = needsOnboarding
        self.storeProvider = storeProvider
        self.subscription = subscription
        self.spotlight = spotlight
        self.dailiesVM = DailiesViewModel(store: initialStore, spotlight: spotlight)
        // Hand the indexer to the subscription manager so the lapse transition
        // triggers a deindex-all without AppModel needing to observe status.
        subscription.attachSpotlightIndexer(spotlight)

        if needsOnboarding {
            self.onboardingVM = nil
            self.onboardingVM = OnboardingViewModel { [weak self] in
                self?.completeOnboarding()
            }
        }
    }

    /// Called by OnboardingViewModel after the master key is stored. Rebinds the
    /// feature view model to the now-openable production store and seeds the first
    /// Takes, then flips to the main app.
    private func completeOnboarding() {
        if let store = storeProvider() {
            seedIfEmpty(store)
            rebind(to: store)
        } else {
            // The master key was stored but the encrypted store failed to open.
            // Previously this fell through SILENTLY onto the launch in-memory
            // store — everything the user wrote was lost on the next launch with
            // zero indication. Surface it through the existing non-blocking
            // notice strip; data recovery is via restart (or, worst case, the
            // privacy phrase).
            lastSyncError = "Your encrypted library couldn't be opened, so changes aren't being saved to this device yet. Please restart Catchlight."
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
        // Carry the same Spotlight indexer through the store swap that follows
        // onboarding completion — without this, post-onboarding Takes wouldn't
        // be indexed until the next app launch.
        dailiesVM = DailiesViewModel(store: store, spotlight: spotlight)
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

    /// Task 6.13 — friendly string for a stale or unresolvable cloud-folder
    /// bookmark. Exposed for testability.
    static func friendlyBookmarkErrorMessage(for error: Wiring.CloudBookmarkError) -> String {
        switch error {
        case .stale:
            return "Your cloud folder is no longer available. Open Settings → Cloud Storage to re-pick it."
        case .unresolvable:
            return "Your cloud folder couldn't be opened. Open Settings → Cloud Storage to choose a new one."
        }
    }

    /// Report a bookmark-health issue through the same non-blocking strip the
    /// sync engine uses. Called by CatchlightApp on scenePhase → active.
    func reportBookmarkError(_ error: Wiring.CloudBookmarkError) {
        lastSyncError = Self.friendlyBookmarkErrorMessage(for: error)
    }

    /// Add to the running quarantine count from the latest sync pass.
    func reportQuarantined(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        quarantinedCount += ids.count
    }

    /// Strip-side actions — clear the matching state.
    func clearSyncError() { lastSyncError = nil }
    func clearQuarantineNotice() { quarantinedCount = 0 }

    // MARK: - Task 6.20 / 6.21 — subscription gating

    /// Returns true if the caller may proceed with a create/edit action.
    /// When false, opens the paywall as a side-effect so the call-site can
    /// simply branch on the bool.
    @discardableResult
    func ensureEntitled() -> Bool {
        if subscriptionStatus.isEntitled { return true }
        ui.isPaywallPresented = true
        return false
    }

    /// Post-onboarding hook: if the user is unentitled, surface the paywall.
    /// Idempotent — safe to call from any "main app appeared" code path.
    func presentPaywallIfNeededAfterOnboarding() {
        guard !needsOnboarding else { return }
        if !subscriptionStatus.isEntitled {
            ui.isPaywallPresented = true
        }
    }

    // MARK: - Previews

    static func preview(store: TakeStore, onboarded: Bool) -> AppModel {
        AppModel(
            needsOnboarding: !onboarded,
            initialStore: store,
            storeProvider: { store },
            subscription: SubscriptionManager()
        )
    }
}
