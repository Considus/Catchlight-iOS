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
        // One wipe, shared with the shipping "Start over" (see `AccountReset`). The DEBUG aid
        // additionally clears the entitlement flag, so a reset here simulates a genuinely
        // fresh install; the shipping path deliberately does not.
        AccountReset.wipe(clearingEntitlement: true)

        // Give the destructive writes a beat to flush, then terminate. The next cold launch
        // re-derives `needsOnboarding` from the (now absent) master key. Quitting is against
        // the HIG and the SHIPPING path must not do it — it is tolerable only because this
        // whole file is `#if DEBUG` and cannot reach a user.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            exit(0)
        }
    }
}
#endif
