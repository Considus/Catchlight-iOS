//
//  AccountReset.swift
//  Catchlight
//
//  The shipping "Start over" wipe (D-253, owner 2026-09-04).
//
//  WHY THIS EXISTS. `Wiring` computes `onboarded = MasterKeyKeychain.exists()`, and iOS
//  keychain items survive app deletion, so once a master key exists a user can never reach
//  onboarding again — not by deleting the app, not by any control in Settings. That is fine
//  until the master key is present WITHOUT its privacy phrase (D-253): the app works, but the
//  account can never be recovered, and there was no way out. This is the way out.
//
//  🚨 WHAT A RESET DESTROYS, and why the export is the only route back. Every key derives
//  from the master key by HKDF with no wrapping layer (`KeyHierarchy`): the SQLCipher DB key,
//  the manifest HMAC key, the manifest body key, and the per-item AES-GCM keys. A NEW master
//  key therefore cannot decrypt anything written under the old one — including everything
//  already synced to the cloud folder. Reconnecting that folder afterwards recovers NOTHING.
//  The plaintext Markdown export is the only thing that survives, which is why the flow
//  offers it before it will proceed.
//
//  This file is NOT `#if DEBUG`. `DebugReset` is the developer aid and now delegates here so
//  there is one wipe, not two that can drift.
//

import Foundation
import CatchlightCore

enum AccountReset {

    /// Wipe this device back to a fresh-install state. Does NOT terminate the process: the
    /// caller shows a terminal "reset complete" screen and the user relaunches.
    ///
    /// Quitting programmatically (which `DebugReset` does, acceptably, as a dev aid) is
    /// against Apple's HIG and reads to a user as a crash, so the shipping path cannot do it.
    ///
    /// - Parameter clearingEntitlement: clears the cached "ever entitled" subscription flag.
    ///   DEBUG-only, to simulate a genuinely fresh install. The shipping reset leaves it
    ///   alone: entitlement is a fact about the Apple ID, not about the account keys, and
    ///   dropping a paying user onto the paywall as the reward for recovering their account
    ///   would be its own bug. StoreKit re-derives it regardless.
    static func wipe(clearingEntitlement: Bool = false) {
        wipeKeychain()
        wipeDefaults(clearingEntitlement: clearingEntitlement)
        wipeStore()
    }

    // MARK: - Keychain

    /// Both secrets. These are what gate onboarding and decryption.
    private static func wipeKeychain() {
        MasterKeyKeychain.delete()
        MnemonicKeychain.delete()
    }

    // MARK: - User defaults

    private static func wipeDefaults(clearingEntitlement: Bool) {
        // Onboarding/orientation step + every user preference, so a reset really does return
        // to fresh-install defaults. (owner 2026-06-16: View/Order were persisting through a
        // reset because they were not listed here when they were added. Anything new that
        // persists a user choice belongs in this list.)
        let standard = UserDefaults.standard
        standard.removeObject(forKey: FirstRunOrientationState.storageKey)
        standard.removeObject(forKey: SettingsViewModel.appearanceDefaultsKey)
        standard.removeObject(forKey: SettingsViewModel.TakeSpacing.defaultsKey)          // "View"
        standard.removeObject(forKey: SettingsViewModel.TakeSort.defaultsKey)             // "Order"
        standard.removeObject(forKey: SettingsViewModel.TimelineArrangement.defaultsKey)  // "Arrangement"
        standard.removeObject(forKey: SettingsViewModel.TakePreview.defaultsKey)          // "Preview"
        standard.removeObject(forKey: SettingsViewModel.ExpandedTakes.defaultsKey)        // per-Take "Expand Take"
        standard.removeObject(forKey: SettingsViewModel.LockAfter.defaultsKey)            // "Lock after"

        // The cloud-folder bookmark goes: its contents are sealed under the OLD master key
        // and are so much scrap to the new one. Same code path the Settings sheet uses.
        Wiring.clearCloudFolderBookmark()

        if clearingEntitlement {
            UserDefaults(suiteName: AppGroup.identifier)?
                .removeObject(forKey: SubscriptionManager.everEntitledDefaultsKey)
        }
    }

    // MARK: - Store

    /// Delegates to the production primitive shared with the Settings → Second device wipe,
    /// so there is one deletion path.
    private static func wipeStore() {
        LocalStoreReset.wipeDatabaseFiles()
    }
}
