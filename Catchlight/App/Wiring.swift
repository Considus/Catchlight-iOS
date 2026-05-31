//
//  Wiring.swift
//  Catchlight (iOS app target)
//
//  The composition root. This is the single place where the platform-agnostic
//  CatchlightCore protocols are bound to their concrete iOS implementations:
//
//      Argon2idDeriving   → LibArgon2            (libargon2)
//      TakeStore          → SQLCipherTakeStore   (SQLCipher, App Group container)
//      CloudFolder        → FileCloudFolder      (Files API, security-scoped bookmark)
//
//  Keeping all the platform glue here means CatchlightCore — and therefore the
//  future Web/Android/Mac ports — never depend on any iOS type.
//

import Foundation
import CatchlightCore

enum Wiring {
    /// The production KDF binding.
    static let argon2: Argon2idDeriving = LibArgon2()

    /// Where the persisted cloud-folder bookmark lives (non-sensitive reference).
    private static let bookmarkDefaultsKey = "catchlight.cloudFolderBookmark"
    private static let saltDefaultsKey = "catchlight.argon2SaltB64"

    // MARK: - Phase 6 UI composition

    /// Open the production SQLCipher store, deriving its key from the Keychain master
    /// key. Returns nil before onboarding (no master key yet) or if the store can't
    /// be opened. The UI falls back to an in-memory store in that window so the app
    /// is always interactive.
    static func makeStore() -> TakeStore? {
        guard MasterKeyKeychain.exists(),
              let masterKey = try? MasterKeyKeychain.retrieve(reason: "Unlock your Takes") else {
            return nil
        }
        let keys = KeyHierarchy(masterKey: masterKey)
        return try? SQLCipherTakeStore(keys: keys)
    }

    /// Build the application-scope model that drives the whole UI. Decides onboarding
    /// vs. main app based on whether a master key already exists, and supplies the
    /// production store provider used after onboarding completes.
    @MainActor
    static func makeAppModel() -> AppModel {
        let onboarded = MasterKeyKeychain.exists()
        // Pre-onboarding (or if the encrypted store can't open yet) we run against an
        // in-memory store so the UI is never dead; it is replaced by the SQLCipher
        // store the moment the master key exists (AppModel rebinds on completion).
        let initialStore: TakeStore = (onboarded ? makeStore() : nil) ?? InMemoryTakeStore()
        return AppModel(
            argon2: argon2,
            needsOnboarding: !onboarded,
            initialStore: initialStore,
            storeProvider: { makeStore() }
        )
    }

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
        let store = try? SQLCipherTakeStore(keys: keys)
        guard let store else { return nil }
        return SyncEngine(store: store, cloud: cloud, keys: keys, argon2Salt: salt)
    }
}
