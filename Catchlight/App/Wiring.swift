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
    /// Fallback URL-string slot used when the user pastes a folder URL instead
    /// of picking through `UIDocumentPickerViewController` (Task 3.12).
    static let cloudFolderURLStringDefaultsKey = "catchlight.cloudFolderURLString"
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
        return try? EncryptedTakeStore(keys: keys)
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
            // Explicit creation times 1s apart: timestamps are truncated to
            // millisecond precision (wire resolution), so two back-to-back
            // `Take()` inits can TIE on createdAt — and a tied newest-first
            // sort is unstable, flipping which row is on top between launches
            // (UI tests assume "Call the framer back" is the top row).
            let base = Date()
            try? store.upsert(Take(createdAt: base.addingTimeInterval(-1),
                                   bodyText: "Buy film for the weekend shoot"))
            try? store.upsert(Take(createdAt: base, bodyText: "Call the framer back"))
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
                storeProvider: { nil },   // never swap stores during a test run
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
    /// (The Argon2 salt requirement is gone — HKDF derivation uses a fixed
    /// domain salt, so the per-account salt had no function. Previously this
    /// guard could silently disable sync if the legacy defaults key was absent.)
    static func makeSyncEngine() -> SyncEngine? {
        guard MasterKeyKeychain.exists() else { return nil }
        guard let cloud = makeCloudFolder() else {
            return nil   // local-only mode
        }
        guard let masterKey = try? MasterKeyKeychain.retrieve(reason: "Sync your Takes") else { return nil }

        let keys = KeyHierarchy(masterKey: masterKey)
        let store = try? EncryptedTakeStore(keys: keys)
        guard let store else { return nil }
        return SyncEngine(store: store, cloud: cloud, keys: keys, deviceId: deviceId())
    }

    /// Resolve the configured cloud folder: the security-scoped bookmark
    /// (preferred, set via "Choose Folder") or the pasted-URL fallback slot.
    /// The URL slot previously was written by Settings but NEVER read by
    /// anything — users who pasted a URL believed sync was configured while the
    /// app silently ran local-only.
    private static func makeCloudFolder() -> FileCloudFolder? {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        if let bookmark = defaults?.data(forKey: bookmarkDefaultsKey),
           let cloud = try? FileCloudFolder(bookmark: bookmark) {
            // The OS flagged the bookmark stale: re-mint and re-persist so
            // access doesn't silently degrade later.
            if cloud.bookmarkWasStale,
               let fresh = try? FileCloudFolder.makeBookmark(for: cloud.folderURL) {
                defaults?.set(fresh, forKey: bookmarkDefaultsKey)
            }
            return cloud
        }
        if let raw = defaults?.string(forKey: cloudFolderURLStringDefaultsKey),
           let url = usableFolderURL(from: raw) {
            return FileCloudFolder(folderURL: url)
        }
        return nil
    }

    /// Accepts a `file://` URL or a plain path, and requires it to be an
    /// existing, readable directory from this sandbox. Shared by
    /// CloudStorageView (validation at save time) and `makeCloudFolder`
    /// (validation at engine construction).
    static func usableFolderURL(from raw: String) -> URL? {
        let url: URL
        if let parsed = URL(string: raw), parsed.isFileURL {
            url = parsed
        } else if raw.hasPrefix("/") {
            url = URL(fileURLWithPath: raw, isDirectory: true)
        } else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: url.path) else {
            return nil
        }
        return url
    }
}
