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

    /// App-entry lock state for an ONBOARDED user (D-042 lock screen). The
    /// encrypted store is no longer opened eagerly at launch — an onboarded user
    /// starts `.locked`, `RootView` shows the branded `LockView`, and the store is
    /// bound only after `attemptUnlock()` succeeds (one iOS `.userPresence` prompt,
    /// never a writable empty fallback). Pre-onboarding and `--uitesting` start
    /// `.unlocked`. `.failed` carries the message the lock screen shows on
    /// cancel/auth-failure or an unopenable library.
    enum LockState: Equatable { case unlocked, locked, unlocking, failed(String) }
    private(set) var lockState: LockState

    /// Set when onboarding completes but the store hasn't opened yet (the user
    /// cancelled the post-onboarding prompt). The first successful `attemptUnlock`
    /// seeds the starter Takes, so seeding survives a cancel-then-retry without the
    /// eager open path having to run.
    private var seedOnNextUnlock = false

    // Feature view model. Available once a store is bound (after onboarding).
    // (Dock redesign 2026-06-10: the timeline is the ONE surface; the former
    // Search/Sequence view models are gone — the dock's live filter narrows
    // the Dailies snapshot directly via SequenceFilter.)
    private(set) var dailiesVM: DailiesViewModel

    /// The live crypto session. Held as a plain reference for IMPERATIVE use
    /// (`adopt(_:)` / `currentKeys()` / `lock()`); it is observed for `isObscured`
    /// in `CatchlightApp` via `@StateObject`, not here.
    private let session: SessionController

    /// Builds the encrypted store from an already-unlocked key hierarchy WITHOUT a
    /// Keychain prompt (`Wiring.makeStore(keys:)`). Used by the unlock path AND the
    /// onboarding-completion path (which opens from the just-derived key).
    private let makeStoreFromKeys: (KeyHierarchy) -> TakeStore?

    /// Retrieves the master key from the Keychain (presenting the Face ID/passcode
    /// sheet) and returns the unlocked key hierarchy, or throws on cancel/failure.
    /// `@Sendable` because `attemptUnlock` runs it OFF the main actor so the lock
    /// screen never freezes; injected so the state machine is unit-testable without
    /// the real Keychain.
    private let unlockKeys: @Sendable () throws -> KeyHierarchy

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
         session: SessionController,
         makeStoreFromKeys: @escaping (KeyHierarchy) -> TakeStore?,
         unlockKeys: @escaping @Sendable () throws -> KeyHierarchy,
         lockState: LockState = .unlocked,
         subscription: SubscriptionManager,
         spotlight: SpotlightIndexing = NoopSpotlightIndexer()) {
        self.needsOnboarding = needsOnboarding
        self.session = session
        self.makeStoreFromKeys = makeStoreFromKeys
        self.unlockKeys = unlockKeys
        self.lockState = lockState
        self.subscription = subscription
        self.spotlight = spotlight
        self.dailiesVM = DailiesViewModel(store: initialStore, spotlight: spotlight)
        // Hand the indexer to the subscription manager so the lapse transition
        // triggers a deindex-all without AppModel needing to observe status.
        subscription.attachSpotlightIndexer(spotlight)

        if needsOnboarding {
            self.onboardingVM = nil
            self.onboardingVM = OnboardingViewModel { [weak self] masterKeyData in
                self?.completeOnboarding(with: masterKeyData)
            }
        }
    }

    /// Called by OnboardingViewModel after the master key is stored. Rebinds the
    /// feature view model to the now-openable production store and seeds the first
    /// Takes, then flips to the main app.
    private func completeOnboarding(with masterKeyData: Data) {
        onboardingVM = nil
        needsOnboarding = false
        // Open the store directly from the key we JUST derived — no Keychain read,
        // so NO Face ID/passcode prompt right after setup (the user lands straight in
        // the seeded timeline). The `.userPresence` prompt first appears on the next
        // cold launch via LockView. `KeyHierarchy(masterKeyBytes:)` is identical to
        // the cold-launch Keychain-read hierarchy for the same bytes, so the seeded
        // Takes decrypt then.
        let keys = KeyHierarchy(masterKeyBytes: masterKeyData)
        session.adopt(keys)
        if let store = makeStoreFromKeys(keys) {
            seedIfEmpty(store)
            rebind(to: store)
            lockState = .unlocked
        } else {
            // The store genuinely couldn't open (corrupt / I/O) — fall back to the
            // lock screen so a relaunch/retry can recover; seed on that first unlock.
            seedOnNextUnlock = true
            lockState = .locked
        }
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

    // MARK: - D-042 — app-entry lock screen

    /// Drive the unlock for an onboarded user: present the iOS `.userPresence`
    /// prompt (run OFF the main actor so the lock screen never freezes), then bind
    /// the encrypted store from the unlocked keys. Distinguishes auth-cancel from an
    /// unopenable library; NEVER falls back to a writable empty store. Called by
    /// `LockView` (`await`).
    func attemptUnlock() async {
        guard lockState != .unlocking else { return }
        lockState = .unlocking
        let keys: KeyHierarchy
        do {
            // The Keychain retrieve BLOCKS until the user answers the Face ID/passcode
            // sheet — run it off the main actor so the UI stays responsive.
            let retrieve = unlockKeys
            keys = try await Task.detached(priority: .userInitiated) { try retrieve() }.value
        } catch {
            lockState = .failed("Couldn't unlock. Authenticate to open your Takes.")
            return
        }
        session.adopt(keys)
        guard let store = makeStoreFromKeys(keys) else {
            // Auth succeeded but the encrypted DB couldn't open (corrupt / I/O).
            // Distinct from cancel — retrying auth won't help. Surface via the
            // existing strip too, but stay locked (no writable fallback).
            lastSyncError = "Your encrypted library couldn't be opened, so changes aren't being saved to this device yet. Please restart Catchlight."
            lockState = .failed("Your encrypted library couldn't be opened. Please restart Catchlight.")
            return
        }
        if seedOnNextUnlock {
            // First unlock after onboarding (the post-onboarding prompt was
            // cancelled and retried here) — seed the starter Takes.
            seedIfEmpty(store)
            seedOnNextUnlock = false
        }
        rebind(to: store)        // bind the REAL store before the UI un-gates
        session.clearObscured()  // drop the privacy curtain so it can't flash post-Face ID
        lockState = .unlocked
    }

    /// When the app last entered the background, for the time-away re-lock. iOS
    /// can't reliably tell a SUSPENDED app that the device locked, so we re-lock on
    /// return if we were away longer than `relockGrace` (the reliable proxy for
    /// "you stepped away / the phone auto-locked"). Quick app-switches stay unlocked.
    private var backgroundedAt: Date?

    /// Record the moment we leave the foreground (scene `.background`).
    func noteEnteredBackground() { backgroundedAt = Date() }

    /// On returning to the foreground, re-lock if we were away longer than the grace
    /// window. Always clears the timestamp. No-op on a cold launch (no timestamp) or
    /// if already locked (e.g. the device-lock notification beat us to it).
    func relockIfAwayTooLong() {
        let since = backgroundedAt
        backgroundedAt = nil
        guard lockState == .unlocked, let since else { return }
        // The grace window is the user's "Lock after" setting (read fresh each time).
        if Date().timeIntervalSince(since) >= SettingsViewModel.LockAfter.current.seconds {
            relock()
        }
    }

    /// Re-lock when the device itself locks (`protectedDataWillBecomeUnavailable`).
    /// Tears down the live keys + the encrypted store and returns to `.locked` so
    /// the next foreground shows `LockView` again — re-lock thus follows the
    /// device's own lock (the user's iOS Auto-Lock), not an app-defined timer.
    /// No-op while onboarding (no key yet) or already locked.
    func relock() {
        guard !needsOnboarding, lockState == .unlocked else { return }
        // Auto-save a mid-edit Take BEFORE the store is torn down (owner 2026-06-17 —
        // locking should preserve in-progress work, not discard it). Runs DailiesView's
        // own save path while the encrypted store is still bound; must precede
        // `session.lock()` / the rebind below, after which a write would be lost.
        ui.commitInlineEdit?()
        ui.endEditingInPlace()              // drop in-place edit focus (the draft lives in DailiesView, torn down with the locked timeline)
        session.lock()                      // zero the session's keys + decrypted cache
        Wiring.clearSessionKeys()           // drop the cached keys used by sync
        rebind(to: InMemoryTakeStore())     // tear down the encrypted store (never written while locked)
        lockState = .locked
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
        // Belt-and-suspenders: while locked the UI is fully covered by LockView so
        // mutation entry points are unreachable — but never let a create/edit slip
        // through against the locked placeholder store (no side effects).
        guard lockState == .unlocked else { return false }
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
            session: SessionController(),
            makeStoreFromKeys: { _ in store },
            unlockKeys: { KeyHierarchy(masterKeyBytes: Data(repeating: 0, count: 32)) },
            lockState: .unlocked,
            subscription: SubscriptionManager()
        )
    }
}
