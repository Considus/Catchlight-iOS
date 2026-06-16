//
//  DebugReset.swift
//  Catchlight (iOS app target) — DEBUG-only developer aid
//
//  On-device testing aid (fix pass 1, section 2). The iOS Keychain survives app
//  deletion, so a physical device has no other way to re-trigger onboarding once
//  a master key exists. This wipes EVERYTHING that makes the app a fresh install
//  and terminates the process so the next launch re-evaluates
//  `needsOnboarding = !MasterKeyKeychain.exists()` and lands on onboarding.
//
//  The ENTIRE file is wrapped in `#if DEBUG`, so it cannot compile into a
//  Release / TestFlight archive. There is no way to ship this.
//

#if DEBUG
import Foundation
import UIKit
import CatchlightCore

enum DebugReset {

    /// Wipe the app back to a fresh-install state, then terminate so the next
    /// launch shows onboarding. DEBUG only.
    ///
    /// What it clears, in order:
    ///   • Keychain master key (+ its Secure-Enclave wrapping key) and mnemonic —
    ///     the secrets that gate onboarding and decryption.
    ///   • Onboarding / orientation + all preference user defaults (appearance,
    ///     View/Order timeline settings, Lock-after).
    ///   • App-group cloud-folder bookmark / URL keys.
    ///   • The `everEntitled` subscription flag (app-group defaults).
    ///   • The local SQLite store (all Takes + sequences) by removing the
    ///     Database directory from the app-group container.
    @MainActor
    static func wipeAndRelaunch() {
        wipeKeychain()
        wipeDefaults()
        wipeStore()

        // Give the destructive writes a beat to flush, then terminate. The next
        // cold launch re-derives `needsOnboarding` from the (now absent) master
        // key. Terminating is acceptable for a DEBUG-only action and is the
        // simplest reliable way to force a clean re-evaluation of launch state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            exit(0)
        }
    }

    // MARK: - Keychain

    private static func wipeKeychain() {
        MasterKeyKeychain.delete()
        MnemonicKeychain.delete()
    }

    // MARK: - User defaults

    private static func wipeDefaults() {
        // Standard defaults: onboarding/orientation step + all user preferences, so a
        // reset truly returns to fresh-install defaults. (owner 2026-06-16: View/Order
        // were persisting through a reset — they weren't listed here when added.)
        let standard = UserDefaults.standard
        standard.removeObject(forKey: FirstRunOrientationState.storageKey)
        standard.removeObject(forKey: SettingsViewModel.appearanceDefaultsKey)
        standard.removeObject(forKey: SettingsViewModel.TakeSpacing.defaultsKey)   // "View"
        standard.removeObject(forKey: SettingsViewModel.TakeSort.defaultsKey)      // "Order"
        standard.removeObject(forKey: SettingsViewModel.TakePreview.defaultsKey)   // "Preview"
        standard.removeObject(forKey: SettingsViewModel.LockAfter.defaultsKey)     // "Lock after"

        // App-group defaults: cloud-folder bookmark / URL fallback + the
        // "ever entitled" subscription flag. `clearCloudFolderBookmark` removes
        // both cloud keys via the same code the Settings sheet uses.
        Wiring.clearCloudFolderBookmark()
        UserDefaults(suiteName: AppGroup.identifier)?
            .removeObject(forKey: SubscriptionManager.everEntitledDefaultsKey)
    }

    // MARK: - Store

    /// Remove the entire encrypted store directory from the app-group container.
    /// Deleting the files (rather than issuing `delete` per Take through an
    /// unlocked store) makes this work even when the store can't be opened, and
    /// clears the SQLite WAL/SHM sidecars and any sequences in one move.
    private static func wipeStore() {
        let dbDir = AppGroup.containerURL().appendingPathComponent("Database", isDirectory: true)
        try? FileManager.default.removeItem(at: dbDir)
        // Also remove a legacy root-level db file if one was ever migrated from.
        let legacy = AppGroup.containerURL().appendingPathComponent("catchlight.db")
        try? FileManager.default.removeItem(at: legacy)
    }
}
#endif
