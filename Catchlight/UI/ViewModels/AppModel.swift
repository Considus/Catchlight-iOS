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
    /// Dismiss button or its 8-second auto-dismiss timer. Each non-nil value is recorded to
    /// the content-free diagnostics log (D-085) for Notice History + export.
    var lastSyncError: String? {
        didSet { if let lastSyncError { DiagnosticsLog.shared.record(.sync, lastSyncError) } }
    }

    /// Number of Takes the last sync pass refused to decrypt because their
    /// per-blob HMAC didn't verify (Task 3.9). UUIDs are deliberately NOT exposed
    /// to the UI — privacy. Drives a second non-blocking strip when > 0; tapping
    /// Dismiss in the view resets to zero. A new non-zero count is recorded to the
    /// diagnostics log (count only — no UUIDs).
    var quarantinedCount: Int = 0 {
        didSet {
            if quarantinedCount > 0, quarantinedCount != oldValue {
                DiagnosticsLog.shared.record(.quarantine,
                    "\(quarantinedCount) Take\(quarantinedCount == 1 ? "" : "s") couldn't be verified and \(quarantinedCount == 1 ? "was" : "were") skipped.")
            }
        }
    }

    /// Fire a manual "Sync Now" pass (owner 2026-06-21). Wired by `CatchlightApp`
    /// to the shared `BackgroundSyncCoordinator` so a tap reuses the same
    /// conflict / remote-change callbacks as an automatic pass. nil until wired
    /// (previews / tests) — the Cloud Storage button is a no-op in that case.
    var performManualSync: (() -> Void)?

    /// Set true when a cross-device RESTORE completes with no cloud folder yet
    /// configured (chunk 3c, D-087). A restore lands on an empty timeline — the real
    /// Takes live in the cloud folder — so the empty state shows a guidance card that
    /// walks the user to connect that folder rather than the generic "first Take is
    /// waiting" line. Cleared once a folder is connected or the user dismisses.
    /// In-memory only: the phrase is already stored, so Settings → Cloud Storage
    /// remains a reliable fallback if the app is quit before connecting.
    var restoreAwaitingFolder: Bool = false

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

    /// A capture (widget / intent / Control) that arrived while the app was LOCKED,
    /// held as an in-memory draft so the user can type IMMEDIATELY — the master key
    /// (Face ID) is deferred to save ("one glance → type", owner 2026-06-23). While
    /// this is non-nil and the app is locked, `RootView` shows `LockedCaptureView`
    /// (the blank editor only — no timeline, no decrypted content) instead of
    /// `LockView`. Nil = the normal lock screen. The single Face ID fires in
    /// `saveLockedCapture`, the first moment the encrypted store is actually needed.
    var lockedCapture: Take?

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
        // Bulk re-index on RECOVERY from a lapse (2026-07-01): the lapse wipes
        // the Spotlight index, and per-save re-indexing alone left every
        // un-resaved Take invisible to system search forever after a transient
        // false lapse. AppModel holds both the store and the indexer, so the
        // rebuild lives here. No-op while locked (placeholder store is empty).
        subscription.onRecoveredFromLapse = { [weak self] in
            guard let self, self.lockState == .unlocked,
                  let takes = try? self.dailiesVM.store.allTakes() else { return }
            takes.forEach { self.spotlight.index($0) }
        }

        if needsOnboarding {
            self.onboardingVM = nil
            self.onboardingVM = OnboardingViewModel { [weak self] masterKeyData, isRestore in
                self?.completeOnboarding(with: masterKeyData, isRestore: isRestore)
            }
        }
    }

    /// Called by OnboardingViewModel after the master key is stored. Rebinds the
    /// feature view model to the now-openable production store and (for a fresh
    /// generate) seeds the first Takes, then flips to the main app.
    ///
    /// `isRestore` — a cross-device restore MUST NOT seed. The restored user's real
    /// Takes arrive from the cloud folder on the first sync; seeding five example
    /// Takes locally would (a) show examples the user never wanted and (b) push those
    /// examples UP into their real data the moment the folder is connected. So a
    /// restore lands on an empty timeline that fills in once the folder is connected
    /// (chunk 3, D-087). Applies to BOTH the immediate open and the seed-on-next-unlock
    /// fallback below.
    private func completeOnboarding(with masterKeyData: Data, isRestore: Bool) {
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
            if !isRestore { seedIfEmpty(store) }
            rebind(to: store)
            lockState = .unlocked
            // A restore lands empty and needs the cloud folder connected to pull the
            // user's Takes — surface the guidance card unless a folder is already set.
            if isRestore { restoreAwaitingFolder = !cloudFolderConfigured }
        } else {
            // The store genuinely couldn't open (corrupt / I/O) — fall back to the
            // lock screen so a relaunch/retry can recover; seed on that first unlock
            // (never for a restore).
            seedOnNextUnlock = !isRestore
            lockState = .locked
        }
    }

    /// Whether a cloud-folder bookmark is already persisted (App Group defaults).
    private var cloudFolderConfigured: Bool {
        UserDefaults(suiteName: AppGroup.identifier)?
            .data(forKey: Wiring.bookmarkDefaultsKey) != nil
    }

    /// Persist a picked cloud folder and immediately sync — the single connect path
    /// shared by Settings → Cloud Storage and the post-restore guidance card. Saving
    /// the bookmark alone isn't enough: the sync coordinator otherwise only fires on
    /// app-active / background / the Sync Now button, so a freshly-connected folder
    /// would sit idle. Firing here is also what PULLS a restored user's Takes down
    /// (`pullInbound`'s manifest-HMAC check is the right-phrase-for-this-folder gate).
    /// Returns a user-readable error string on failure, nil on success. D-087.
    @discardableResult
    func connectCloudFolder(_ url: URL) -> String? {
        do {
            let bookmark = try FileCloudFolder.makeBookmark(for: url)
            UserDefaults(suiteName: AppGroup.identifier)?
                .set(bookmark, forKey: Wiring.bookmarkDefaultsKey)
            restoreAwaitingFolder = false   // guidance served its purpose
            performManualSync?()
            return nil
        } catch {
            return "Couldn't save that folder: \(error.localizedDescription)"
        }
    }

    // MARK: - Second device (Settings re-key, D-087)

    /// Re-key THIS device to the account behind `words`, in process. Destructive by
    /// necessity: to be in Settings the device is already onboarded, so its local
    /// Takes are sealed under the CURRENT master key. Installing a new key would leave
    /// those rows undecryptable — and the store's read path THROWS on an undecryptable
    /// row rather than hiding it, which breaks the whole timeline. So we wipe the local
    /// store before re-binding under the new key (the user has already confirmed the
    /// warning). The restored account's real Takes then arrive from its cloud folder,
    /// via the same post-restore guidance a fresh-install restore uses.
    ///
    /// Returns a user-readable error string on failure (nil on success):
    ///   • a bad phrase → inline message, NOTHING destroyed (validation is first);
    ///   • a Keychain / store-open fault → message, and the app is left locked so a
    ///     relaunch retries the unlock (the new key is already stored by then).
    @discardableResult
    func replaceAccountForSecondDevice(_ words: [String]) -> String? {
        let cleaned = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        // 1. Validate + derive FIRST — a bad phrase must destroy nothing.
        let bip39: BIP39
        do { bip39 = BIP39(wordlist: try EnglishWordlist.load()) }
        catch { return "Couldn't check your phrase on this device." }
        let masterKeyData: Data
        do { masterKeyData = try PhraseRecovery.recoverMasterKey(from: cleaned, bip39: bip39) }
        catch { return "That doesn't look right. Check the words and try again." }

        // 2. Install the new secrets (overwrites the current account's key + mnemonic).
        do {
            try MasterKeyKeychain.store(masterKeyData)
            try MnemonicKeychain.store(cleaned)
        } catch {
            return "Couldn't secure your account on this device."
        }

        // 3. Drop the old encrypted store (release its SQLite handle), purge the old
        //    account's Takes from the system Spotlight index, and delete the local DB
        //    files so the store re-opens EMPTY under the new key.
        dailiesVM = DailiesViewModel(store: InMemoryTakeStore(), spotlight: spotlight)
        spotlight.deindexAll()
        LocalStoreReset.wipeDatabaseFiles()

        // 4. Re-bind under the new keys — mirrors completeOnboarding's open path
        //    (makeStoreFromKeys primes Wiring.sessionKeys, so no Face ID prompt).
        let keys = KeyHierarchy(masterKeyBytes: masterKeyData)
        session.adopt(keys)
        guard let store = makeStoreFromKeys(keys) else {
            lockState = .locked   // relaunch will retry the unlock with the stored key
            return "Couldn't open your library on this device. Please restart Catchlight."
        }
        rebind(to: store)        // fresh empty store under the new account
        lockState = .unlocked

        // 5. The new account needs its OWN cloud folder — the previous bookmark (if any)
        //    belonged to the old account. Clear it and show the connect-folder guidance,
        //    the same path a fresh-install restore lands on.
        Wiring.clearCloudFolderBookmark()
        restoreAwaitingFolder = true
        return nil
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

    // MARK: - Zero-Face-ID capture (owner 2026-06-23, "one glance → type")

    /// Commit a Take captured while LOCKED. This is where the ONE Face ID fires —
    /// the first moment the encrypted store is actually needed. Flow:
    ///   • a blank draft is discarded WITHOUT prompting (no key needed to throw away
    ///     nothing) — so a tap-and-back-out never shows Face ID;
    ///   • otherwise unlock (Face ID), which binds the real store, then persist;
    ///   • a cancelled/failed unlock leaves `lockedCapture` set so the editor stays
    ///     up with the typed text intact for a retry (owner: "keep it, let me retry");
    ///   • a lapsed user hits the paywall instead of saving (consistent with the dock).
    func saveLockedCapture() async {
        // Read the live draft from the observed property the editor mutates directly —
        // no view-local @State copy that could lag behind the typed text.
        guard let draft = lockedCapture else { return }
        let isBlank = draft.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.isTask && draft.timeReminder == nil
        guard !isBlank else { lockedCapture = nil; return }

        await attemptUnlock()
        // Cancelled / failed: stay in the capture editor (text preserved) for a retry.
        guard lockState == .unlocked else { return }
        guard ensureEntitled() else {
            // Paywall interrupted the save (owner 2026-07-01): HOLD the typed
            // draft for the paywall's outcome — saved if they subscribe, dropped
            // if the paywall closes unsubscribed — instead of destroying it here.
            holdDraftForPaywall(draft)
            lockedCapture = nil
            return
        }

        dailiesVM.save(draft)   // real store is bound by attemptUnlock's rebind
        lockedCapture = nil
    }

    /// Abandon a locked capture without saving — back to the normal lock screen.
    func discardLockedCapture() { lockedCapture = nil }

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

    // MARK: - Draft preservation at the paywall (owner decision 2026-07-01)

    /// A typed draft whose save was interrupted by the paywall. Held until the
    /// paywall resolves: SAVED if the user subscribes, DROPPED if the paywall
    /// closes without an active subscription. Previously all three interrupted
    /// save paths (locked capture, timeline inline edit, Storyboard edit)
    /// silently destroyed the typed text the moment the paywall appeared —
    /// inconsistent with the auth-retry branch and the relock auto-save, both
    /// of which preserve in-progress work. One slot: the paywall is modal, so
    /// at most one interrupted save can be pending.
    private(set) var pendingEntitledSave: Take?

    /// Hold a draft whose `ensureEntitled()` just returned false (the paywall is
    /// presenting) for the paywall's outcome, instead of discarding typed text.
    func holdDraftForPaywall(_ draft: Take) {
        pendingEntitledSave = draft
    }

    /// Resolve the held draft when the paywall dismisses: save it if the user is
    /// now entitled, otherwise drop it (the agreed policy — no subscription, no
    /// write). Idempotent; safe to call on every paywall dismissal.
    func resolvePendingEntitledSave() {
        defer { pendingEntitledSave = nil }
        guard let draft = pendingEntitledSave,
              lockState == .unlocked,
              subscriptionStatus.isEntitled else { return }
        dailiesVM.save(draft)
    }

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
