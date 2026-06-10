//
//  Wiring.swift
//  Catchlight (iOS app target)
//
//  The composition root. This is the single place where the platform-agnostic
//  CatchlightCore protocols are bound to their concrete iOS implementations:
//
//      TakeStore          → SQLiteTakeStore       (SQLite3 + NSFileProtection, App Group container)
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
    /// Fallback URL-string slot used when the user pastes a folder URL instead
    /// of picking through `UIDocumentPickerViewController` (Task 3.12).
    static let cloudFolderURLStringDefaultsKey = "catchlight.cloudFolderURLString"
    private static let saltDefaultsKey = "catchlight.argon2SaltB64"
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
        defaults?.removeObject(forKey: cloudFolderURLStringDefaultsKey)
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
        return try? SQLiteTakeStore(keys: keys)
    }

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
    static func makeAppModel() -> AppModel {
        // `#if DEBUG` so the test hook is COMPLETELY removed from Release
        // archives — a stripped binary cannot land in the UI-test branch even
        // if launched with `--uitesting`. The UI tests run against the Debug
        // scheme (XcodeGen's default for `test` actions), so this gate is
        // transparent to the test suite.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let store = InMemoryTakeStore()
            try? store.upsert(Take(bodyText: "Buy film for the weekend shoot"))
            try? store.upsert(Take(bodyText: "Call the framer back"))
            // UI-test build is treated as fully entitled by default so existing
            // flow tests aren't gated by the paywall. Pass `--uitesting-lapsed`
            // alongside to exercise the paywall path explicitly.
            let manager = SubscriptionManager(defaults: isolatedTestDefaults())
            if !ProcessInfo.processInfo.arguments.contains("--uitesting-lapsed") {
                manager.forceStatusForTesting(.subscribed)
            } else {
                manager.forceStatusForTesting(.lapsed)
            }
            return AppModel(
                needsOnboarding: false,
                initialStore: store,
                storeProvider: { nil },   // never swap stores during a test run
                subscription: manager,
                // UI tests must not touch the real Spotlight index — keep the
                // user's device search results clean across runs.
                spotlight: NoopSpotlightIndexer()
            )
        }
        #endif
        let onboarded = MasterKeyKeychain.exists()
        // Pre-onboarding (or if the encrypted store can't open yet) we run against an
        // in-memory store so the UI is never dead; it is replaced by the SQLite
        // store the moment the master key exists (AppModel rebinds on completion).
        let initialStore: TakeStore = (onboarded ? makeStore() : nil) ?? InMemoryTakeStore()
        let subscriptionDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        return AppModel(
            needsOnboarding: !onboarded,
            initialStore: initialStore,
            storeProvider: { makeStore() },
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
    static func makeSyncEngine() -> SyncEngine? {
        guard MasterKeyKeychain.exists() else { return nil }
        guard let bookmark = UserDefaults(suiteName: AppGroup.identifier)?.data(forKey: bookmarkDefaultsKey) else {
            return nil   // local-only mode
        }
        guard let masterKey = try? MasterKeyKeychain.retrieve(reason: "Sync your Takes") else { return nil }
        guard let cloud = try? FileCloudFolder(bookmark: bookmark) else { return nil }
        guard let saltB64 = UserDefaults(suiteName: AppGroup.identifier)?.string(forKey: saltDefaultsKey),
              let salt = Data(base64Encoded: saltB64) else { return nil }

        let keys = KeyHierarchy(masterKey: masterKey)
        let store = try? SQLiteTakeStore(keys: keys)
        guard let store else { return nil }
        return SyncEngine(store: store, cloud: cloud, keys: keys, argon2Salt: salt, deviceId: deviceId())
    }
}
