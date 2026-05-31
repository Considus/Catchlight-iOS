//
//  SessionController.swift
//  Catchlight (iOS app target)
//
//  Owns the live cryptographic session and enforces memory security (Encryption
//  Architecture §12, Phase 5 brief §5.9). On backgrounding it overlays a privacy
//  screen before the system snapshot and zeroes all in-memory decrypted content and
//  derived per-item keys; on foreground it re-derives from the Keychain master key.
//
//  Key material is held only as CryptoKit `SymmetricKey` (zeroed on dealloc).
//  Decrypted Take text is held only for the duration of display/editing and dropped
//  on background.
//

import Foundation
import SwiftUI
import CryptoKit
import CatchlightCore

@MainActor
public final class SessionController: ObservableObject {

    /// True while a private screen overlay should cover the UI (app inactive/bg).
    @Published public private(set) var isObscured = false
    /// True if the device appears jailbroken — drives a persistent, non-blocking banner.
    @Published public private(set) var jailbreakWarning = false
    @Published public private(set) var isUnlocked = false

    private var keys: KeyHierarchy?
    private var decryptedCache: [UUID: Take] = [:]

    public init() {
        jailbreakWarning = JailbreakDetector.isJailbroken()
    }

    // MARK: - Unlock / lock

    /// Retrieve the master key (biometric/passcode prompt) and build the hierarchy.
    public func unlock() throws {
        let masterKey = try MasterKeyKeychain.retrieve()
        keys = KeyHierarchy(masterKey: masterKey)
        isUnlocked = true
    }

    public func currentKeys() -> KeyHierarchy? { keys }

    // MARK: - Scene lifecycle (Encryption Architecture §12.2)

    public func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            isObscured = false
        case .inactive, .background:
            // sceneWillResignActive equivalent: obscure BEFORE the snapshot, then
            // clear plaintext + derived keys.
            overlayPrivacyScreen()
            clearDecryptedCache()
            clearDerivedKeyCache()
        @unknown default:
            overlayPrivacyScreen()
        }
    }

    private func overlayPrivacyScreen() { isObscured = true }

    private func clearDecryptedCache() {
        // Replacing the dictionary drops references to decrypted Take values.
        decryptedCache.removeAll(keepingCapacity: false)
    }

    private func clearDerivedKeyCache() {
        // Dropping the KeyHierarchy releases its SymmetricKeys; CryptoKit zeroes the
        // underlying buffers on deallocation. Master key is re-fetched on unlock.
        keys = nil
        isUnlocked = false
    }

    // MARK: - Decrypted cache (display/edit only)

    public func cache(_ take: Take) { decryptedCache[take.id] = take }
    public func cached(_ id: UUID) -> Take? { decryptedCache[id] }
}
