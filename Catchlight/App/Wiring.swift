//
//  Wiring.swift
//  Catchlight (iOS app target)
//
//  The composition root. This is the single place where the platform-agnostic
//  CatchlightCore protocols are bound to their concrete iOS implementations:
//
//      TakeStore          → EncryptedTakeStore   (SQLite3, AES-256-GCM payload columns,
//                                                 NSFileProtection, App Group container)
//      CloudFolder        → FileCloudFolder      (Files API, security-scoped bookmark)
//
//  Master-key derivation is performed in-process by CatchlightCore's
//  `MasterKeyDerivation` (HKDF-SHA-256 via CryptoKit) — no platform binding needed.
//
//  Keeping all the platform glue here means CatchlightCore — and therefore the
//  future Web/Android/Mac ports — never depend on any iOS type.
//

import Foundation
import CatchlightCore

enum Wiring {
    /// Where the persisted cloud-folder bookmark lives (non-sensitive reference).
    /// Internal so Settings → Cloud Storage (Task 3.12) writes to the SAME key
    /// the background sync engine reads from below.
    static let bookmarkDefaultsKey = "catchlight.cloudFolderBookmark"
    /// Legacy paste-a-URL slot, retired 2026-06-22 (a typed path can never gain
    /// iOS write access — only iCloud + Dropbox folder-picks work). Kept private
    /// solely to purge any value an earlier build persisted; nothing reads it.
    private static let legacyCloudFolderURLStringKey = "catchlight.cloudFolderURLString"
    private static let deviceIdDefaultsKey = "catchlight.deviceId"

    /// Task 6.13 — resolve a persisted folder bookmark to a URL while surfacing
    /// the stale flag. Returns the URL together with a boolean indicating that
    /// the bookmark is stale (drive unmounted, permissions revoked, file moved).
    /// Callers should treat `isStale == true` as "cloud sync is paused; ask the
    /// user to re-pick the folder." Returns nil when no bookmark exists.
    /// Throws if the bookmark data is present but can't be resolved at all.
    static func resolveCloudFolderURL() throws -> (url: URL, isStale: Bool)? {
        guard let data = UserDefaults(suiteName: AppGroup.identifier)?
            .data(forKey: bookmarkDefaultsKey) else { return nil }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        return (url, stale)
    }

    /// Clear the persisted cloud-folder bookmark and URL fallback. The next
    /// sync attempt will return to local-only mode (no error surfaced — local
    /// only is the documented absence-of-cloud state, not an error).
    static func clearCloudFolderBookmark() {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        defaults?.removeObject(forKey: bookmarkDefaultsKey)
        defaults?.removeObject(forKey: legacyCloudFolderURLStringKey)
    }

    /// Structured cloud-bookmark error so the UI layer can map to a user-
    /// readable string without inspecting NSError-level details.
    enum CloudBookmarkError: Error, Equatable {
        /// Bookmark resolved but the OS reports it is stale (drive unmounted,
        /// permissions revoked, file moved). Sync will fail until the user
        /// re-picks the folder.
        case stale
        /// Bookmark data is present but cannot be resolved at all (corrupt
        /// or referring to a deleted volume).
        case unresolvable
    }

    /// Check the persisted bookmark's health and return a structured error
    /// when the cloud folder is configured but unavailable. Returns nil when:
    ///   • no bookmark is configured (local-only mode), OR
    ///   • the bookmark resolves cleanly and is not stale.
    /// Designed to be cheap to call on scene activation.
    static func checkCloudBookmarkHealth() -> CloudBookmarkError? {
        do {
            guard let resolved = try resolveCloudFolderURL() else { return nil }
            return resolved.isStale ? .stale : nil
        } catch {
            return .unresolvable
        }
    }

    /// Stable per-install device UUID. Generated on first read and persisted in the
    /// App Group `UserDefaults`. Used as `deviceId` in the sync lock file so the
    /// holder of a fresh lock is identifiable.
    static func deviceId() -> UUID {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        if let existing = defaults?.string(forKey: deviceIdDefaultsKey),
           let uuid = UUID(uuidString: existing) {
            return uuid
        }
        let fresh = UUID()
        defaults?.set(fresh.uuidString, forKey: deviceIdDefaultsKey)
        return fresh
    }

    // MARK: - Phase 6 UI composition

    /// In-memory key hierarchy cached after the user's interactive unlock
    /// (2026-06-10, foreground-sync support). The master key itself carries
    /// `.userPresence`, so every fresh Keychain retrieve costs a Face ID
    /// prompt — and is impossible in a background task. Foreground sync
    /// triggers reuse the keys already unlocked for the session instead of
    /// prompting again. Process-lifetime only; never persisted. Main-thread
    /// confined (set in makeStore / read in makeSyncEngine, both main-actor
    /// call paths).
    nonisolated(unsafe) private static var sessionKeys: KeyHierarchy?

    /// Open the production SQLite store, deriving its key from the Keychain master
    /// key. Returns nil before onboarding (no master key yet) or if the store can't
    /// be opened. The UI falls back to an in-memory store in that window so the app
    /// is always interactive.
    static func makeStore() -> TakeStore? {
        guard MasterKeyKeychain.exists(),
              let masterKey = try? MasterKeyKeychain.retrieve(reason: "Unlock your Takes") else {
            return nil
        }
        let keys = KeyHierarchy(masterKey: masterKey)
        guard let store = try? EncryptedTakeStore(keys: keys) else { return nil }
        sessionKeys = keys
        return store
    }

    /// Open the production store from an ALREADY-unlocked key hierarchy — no
    /// Keychain access, so no Face ID/passcode prompt (D-042). The app-entry
    /// unlock path uses this after `SessionController.unlock()` so the single
    /// `.userPresence` prompt belongs to `unlock()` alone (no double-prompt).
    /// Primes `sessionKeys` so foreground sync reuses the same keys.
    static func makeStore(keys: KeyHierarchy) -> TakeStore? {
        guard let store = try? EncryptedTakeStore(keys: keys) else { return nil }
        sessionKeys = keys
        return store
    }

    /// Drop the cached session keys (D-042 re-lock). Called by `AppModel.relock()`
    /// when the device locks, so a subsequent foreground sync can't reuse stale
    /// keys and must wait for a fresh unlock.
    static func clearSessionKeys() { sessionKeys = nil }

    /// Build the application-scope model that drives the whole UI. Decides onboarding
    /// vs. main app based on whether a master key already exists, and supplies the
    /// production store provider used after onboarding completes.
    ///
    /// **UI-test mode** — when the process was launched with `--uitesting`, the model
    /// skips onboarding entirely, runs against a fresh `InMemoryTakeStore` seeded
    /// with two known Takes, and uses no production store provider. This is the
    /// standard XCUITest pattern (Apple's "launchArguments" hand-off) — it gives
    /// the test bundle a known resting state on every launch with no Keychain or
    /// SQLite state to clear between methods.
    @MainActor
    static func makeAppModel(session: SessionController) -> AppModel {
        // `#if DEBUG` so the test hook is COMPLETELY removed from Release
        // archives — a stripped binary cannot land in the UI-test branch even
        // if launched with `--uitesting`. The UI tests run against the Debug
        // scheme (XcodeGen's default for `test` actions), so this gate is
        // transparent to the test suite.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            // Pin the timeline order for deterministic fixtures: the flow tests
            // assume newest-first ("Call the framer back" on top). The app's
            // user-facing DEFAULT is oldest-first (TakeSort, owner 2026-06-16), but
            // a UI test controls its own environment — so force newest-first here.
            UserDefaults.standard.set(SettingsViewModel.TakeSort.newestFirst.rawValue,
                                      forKey: SettingsViewModel.TakeSort.defaultsKey)
            let store = InMemoryTakeStore()
            // Explicit creation times 1s apart: timestamps are truncated to
            // millisecond precision (wire resolution), so two back-to-back
            // `Take()` inits can TIE on createdAt — and a tied newest-first
            // sort is unstable, flipping which row is on top between launches
            // (UI tests assume "Call the framer back" is the top row).
            let base = Date()
            try? store.upsert(Take(createdAt: base.addingTimeInterval(-1),
                                   blocks: [.textLine("Buy film for the weekend shoot")]))
            try? store.upsert(Take(createdAt: base, blocks: [.textLine("Call the framer back")]))
            // UI-test build is treated as fully entitled by default so existing
            // flow tests aren't gated by the paywall. Pass `--uitesting-lapsed`
            // alongside to exercise the paywall path explicitly.
            let manager = SubscriptionManager(defaults: isolatedTestDefaults())
            if !ProcessInfo.processInfo.arguments.contains("--uitesting-lapsed") {
                manager.forceStatusForTesting(.subscribed)
            } else {
                manager.forceStatusForTesting(.lapsed)
            }
            let model = AppModel(
                needsOnboarding: false,
                initialStore: store,
                session: session,
                makeStoreFromKeys: { _ in nil },
                unlockKeys: { throw KeychainError.notFound },   // never invoked: starts unlocked
                lockState: .unlocked,     // UI tests bypass the lock screen entirely
                subscription: manager,
                // UI tests must not touch the real Spotlight index — keep the
                // user's device search results clean across runs.
                spotlight: NoopSpotlightIndexer()
            )
            // First-run orientation state persists in standard UserDefaults
            // across simulator launches, so whichever hint a PREVIOUS run left
            // armed leaked into the next test (e.g. an armed settings hint
            // swallows the first dailies-tab long-press, breaking Flow 6).
            // UI-test runs start with the tour complete; the orientation flow
            // itself is covered by FirstRunOrientationTests (unit).
            model.orientation.step = 5
            return model
        }
        #endif
        let onboarded = MasterKeyKeychain.exists()
        // D-042: an onboarded user starts LOCKED with a non-writable placeholder —
        // the store is NOT opened eagerly here (that fired the `.userPresence`
        // prompt at launch and, on cancel, silently handed back a writable empty
        // InMemoryTakeStore whose contents were lost). The real store is bound by
        // `AppModel.attemptUnlock()` from the session's keys. Pre-onboarding runs
        // unlocked against an in-memory store (replaced on completion).
        let initialStore: TakeStore = InMemoryTakeStore()
        let lockState: AppModel.LockState = onboarded ? .locked : .unlocked
        let subscriptionDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        return AppModel(
            needsOnboarding: !onboarded,
            initialStore: initialStore,
            session: session,
            makeStoreFromKeys: { keys in makeStore(keys: keys) }, // unlock + onboarding open (no prompt)
            unlockKeys: {                                         // the `.userPresence` prompt — runs off-main
                let masterKey = try MasterKeyKeychain.retrieve(reason: "Unlock your Takes")
                return KeyHierarchy(masterKey: masterKey)
            },
            lockState: lockState,
            subscription: SubscriptionManager(defaults: subscriptionDefaults),
            spotlight: CoreSpotlightIndexer()
        )
    }

    #if DEBUG
    /// Per-launch ephemeral defaults so UI-test runs never inherit a real user's
    /// "ever subscribed" flag between machines.
    private static func isolatedTestDefaults() -> UserDefaults {
        let name = "catchlight.uitesting.subscription"
        let d = UserDefaults(suiteName: name) ?? .standard
        d.removePersistentDomain(forName: name)
        return d
    }
    #endif

    /// Build a SyncEngine if the app is unlocked AND a cloud folder is configured.
    /// Returns nil in local-only mode or when locked (used by background sync).
    /// (The Argon2 salt requirement is gone — HKDF derivation uses a fixed
    /// domain salt, so the per-account salt had no function. Previously this
    /// guard could silently disable sync if the legacy defaults key was absent.)
    static func makeSyncEngine() -> SyncEngine? {
        #if DEBUG
        // UI-test runs must never touch a real cloud folder or keychain —
        // the foreground triggers fire on every launch/background transition,
        // so without this guard a dev simulator with live data would sync
        // during XCUITest runs.
        if ProcessInfo.processInfo.arguments.contains("--uitesting") { return nil }
        #endif
        // Sync disabled entirely (owner 2026-06-21) — the absolute kill-switch:
        // never build an engine, so no path (manual button included) can sync.
        if SettingsViewModel.SyncMode.current == .disabled { return nil }
        guard MasterKeyKeychain.exists() else { return nil }
        guard let cloud = makeCloudFolder() else {
            return nil   // local-only mode
        }
        // Auto-create the user-facing `Import/` drop folder so it's present from the
        // first sync, on existing setups too (owner 2026-06-22). Idempotent; runs
        // before the keys guard since folder creation needs no master key.
        cloud.ensureSubfolder(ImportCoordinator.importFolderName)
        // Sync NEVER authenticates — only the app-entry unlock owns the Face ID prompt
        // (D-042). Reuse the keys the unlock cached; if the app isn't unlocked yet
        // (`sessionKeys` nil), SKIP this sync pass rather than retrieving the master key
        // ourselves. That fallback fired a SECOND Face ID sheet ("Sync your Takes") when
        // a launch sync raced ahead of the unlock on a cold start with a cloud folder
        // configured (owner 2026-06-20). A post-unlock trigger (CatchlightApp) re-runs
        // sync once the keys are cached, so nothing is lost. (Background tasks can't show
        // a prompt anyway, so skip-when-locked was always the correct behaviour there.)
        guard let keys = sessionKeys else { return nil }
        let store = try? EncryptedTakeStore(keys: keys)
        guard let store else { return nil }
        return SyncEngine(store: store, cloud: cloud, keys: keys, deviceId: deviceId())
    }

    /// Resolve the configured cloud folder from the security-scoped bookmark set
    /// via "Choose folder from Files". (The paste-a-URL fallback was removed
    /// 2026-06-22 — a typed path can never gain iOS write access, so it only ever
    /// ran local-only while appearing configured.)
    private static func makeCloudFolder() -> FileCloudFolder? {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        guard let bookmark = defaults?.data(forKey: bookmarkDefaultsKey),
              let cloud = try? FileCloudFolder(bookmark: bookmark) else {
            return nil
        }
        // The OS flagged the bookmark stale: re-mint and re-persist so access
        // doesn't silently degrade later.
        if cloud.bookmarkWasStale,
           let fresh = try? FileCloudFolder.makeBookmark(for: cloud.folderURL) {
            defaults?.set(fresh, forKey: bookmarkDefaultsKey)
        }
        return cloud
    }
}
