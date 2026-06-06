//
//  Keychain.swift
//  Catchlight (iOS app target)
//
//  Master-key storage in the iOS Keychain / Secure Enclave (Encryption Architecture
//  §9, Phase 5 brief §5.7). This file requires the iOS SDK (Security framework with
//  the iOS Keychain semantics) and is NOT part of the platform-agnostic
//  CatchlightCore package.
//
//  NON-NEGOTIABLE INVARIANTS:
//    • kSecAttrAccessibleWhenUnlockedThisDeviceOnly — key never migrates off-device
//      and is only accessible while the device is unlocked.
//    • kSecAttrSynchronizable: false — the key MUST NOT sync to iCloud Keychain.
//      Setting this true would put the master key on Apple's servers and destroy
//      the zero-knowledge guarantee.
//    • .userPresence — Face ID / Touch ID / passcode required before retrieval.
//    • .privateKeyUsage — binds to the Secure Enclave.
//    • access group "$(AppIdentifierPrefix)com.considus.catchlight" — shared with
//      future extensions (Share Sheet, Widgets, Shortcuts). Requires the
//      `keychain-access-groups` entitlement on the build; without that, queries
//      fail with OSStatus -34018. Configured in Catchlight.entitlements
//      (Keychain Sharing capability) and signed with the team prefix at build
//      time.
//

import Foundation
import Security
import CryptoKit
import LocalAuthentication

public enum KeychainError: Error {
    case storeFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case accessControlCreationFailed
    case notFound
}

public struct MasterKeyKeychain {
    private static let service = "com.considus.catchlight"
    private static let account = "master-key"
    // Keychain access group — must EXACTLY match the entitled string in the signed
    // binary. The entitlements file uses `$(AppIdentifierPrefix)com.considus.catchlight`,
    // which Xcode resolves at build time to `<TEAM_ID>.com.considus.catchlight`. That
    // substitution only happens for plist/entitlements files, NOT in Swift source —
    // passing the literal `"$(AppIdentifierPrefix)..."` here would fail with
    // OSStatus -34018 because the binary is entitled to the *resolved* group, not
    // the unresolved template string.
    //
    // Team prefix YTPP9HU9F9 = Mark Stradling (project.yml DEVELOPMENT_TEAM).
    // If the team changes, update both this constant AND project.yml.
    private static let accessGroup = "YTPP9HU9F9.com.considus.catchlight"

    /// Build the access-control object. On Secure-Enclave-capable hardware the full
    /// flag set is used; on the Simulator (no Secure Enclave) `.privateKeyUsage` is
    /// dropped (Encryption Architecture §9.3 / brief §5.8) — logged internally only.
    private static func accessControl() throws -> SecAccessControl {
        let flags: SecAccessControlCreateFlags = SecureEnclave.isAvailable
            ? [.userPresence, .privateKeyUsage]
            : [.userPresence]   // Simulator fallback; never shown to the user
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            flags,
            nil
        ) else { throw KeychainError.accessControlCreationFailed }
        return access
    }

    /// Store (or replace) the 32-byte master key.
    public static func store(_ masterKeyData: Data) throws {
        let access = try accessControl()
        let query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecAttrAccessGroup as String:    accessGroup,
            kSecValueData as String:          masterKeyData,
            kSecAttrAccessControl as String:  access,
            kSecAttrSynchronizable as String: false   // CRITICAL: must not sync to iCloud Keychain
        ]
        SecItemDelete(query as CFDictionary)           // remove any existing entry first
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.storeFailed(status) }
    }

    /// Retrieve the master key as a CryptoKit `SymmetricKey`. Triggers biometric /
    /// passcode prompt because of `.userPresence`.
    /// - Parameter reason: the LAContext prompt reason shown to the user.
    public static func retrieve(reason: String = "Unlock your Takes") throws -> SymmetricKey {
        let context = LAContext()
        context.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecAttrAccessGroup as String:    accessGroup,
            kSecReturnData as String:         true,
            kSecMatchLimit as String:         kSecMatchLimitOne,
            kSecAttrSynchronizable as String: false,
            kSecUseAuthenticationContext as String: context
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw status == errSecItemNotFound ? KeychainError.notFound : KeychainError.retrieveFailed(status)
        }
        guard let data = item as? Data else { throw KeychainError.notFound }
        return SymmetricKey(data: data)
    }

    public static func exists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecMatchLimit as String:      kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    public static func delete() {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
            kSecAttrAccessGroup as String: accessGroup
        ]
        SecItemDelete(query as CFDictionary)
    }
}
