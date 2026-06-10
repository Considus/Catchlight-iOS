//
//  Keychain.swift
//  Catchlight (iOS app target)
//
//  Master-key storage in the iOS Keychain, hardware-bound via the Secure Enclave
//  (Encryption Architecture §9, Phase 5 brief §5.7). This file requires the iOS SDK
//  (Security framework with the iOS Keychain semantics) and is NOT part of the
//  platform-agnostic CatchlightCore package.
//
//  DESIGN (revised 2026-06-10):
//  A generic-password item can never itself be Secure-Enclave-resident, and
//  `kSecAccessControlPrivateKeyUsage` is only valid on Secure Enclave private keys —
//  applying it to a password item makes the item unusable on real hardware. So the
//  master key is now wrapped instead of flagged:
//
//    • Secure-Enclave hardware: a permanent SE P-256 key (".userPresence" +
//      ".privateKeyUsage" on the SE key itself) is generated once. The 32-byte
//      master key is ECIES-encrypted to that key and the ciphertext is stored as a
//      generic password. Decryption is only possible inside this device's Secure
//      Enclave and triggers the Face ID / Touch ID / passcode prompt.
//    • Simulator (no Secure Enclave): the raw key is stored as a generic password
//      protected by ".userPresence" access control.
//
//  The stored payload carries a 1-byte format prefix so the two shapes can never
//  be confused: 0x01 = raw (simulator), 0x02 = SE-wrapped ECIES ciphertext.
//
//  NON-NEGOTIABLE INVARIANTS:
//    • kSecAttrAccessibleWhenUnlockedThisDeviceOnly — key never migrates off-device
//      and is only accessible while the device is unlocked.
//    • kSecAttrSynchronizable: false — the key MUST NOT sync to iCloud Keychain.
//      Setting this true would put the master key on Apple's servers and destroy
//      the zero-knowledge guarantee.
//    • User presence (Face ID / Touch ID / passcode) is required before the master
//      key can be recovered — enforced on the SE key (hardware path) or on the
//      password item (simulator path).
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
    case secureEnclaveFailed(String)
    case malformedStoredKey
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
    private static let accessGroup = KeychainConfig.accessGroup

    /// Application tag for the permanent Secure Enclave wrapping key.
    private static let seKeyTag = Data("com.considus.catchlight.master-key-wrap".utf8)
    /// ECIES algorithm used to wrap the master key under the SE public key.
    private static let wrapAlgorithm = SecKeyAlgorithm.eciesEncryptionCofactorVariableIVX963SHA256AESGCM

    /// Stored payload format prefix.
    private enum Format: UInt8 {
        case raw = 0x01        // simulator: raw key bytes, item carries .userPresence
        case seWrapped = 0x02  // hardware: ECIES ciphertext under the SE key
    }

    // MARK: - Store

    /// Store (or replace) the 32-byte master key.
    public static func store(_ masterKeyData: Data) throws {
        if SecureEnclave.isAvailable {
            let privateKey = try fetchOrCreateSEKey()
            guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
                throw KeychainError.secureEnclaveFailed("SecKeyCopyPublicKey returned nil")
            }
            var error: Unmanaged<CFError>?
            guard let ciphertext = SecKeyCreateEncryptedData(
                publicKey, wrapAlgorithm, masterKeyData as CFData, &error
            ) as Data? else {
                let detail = (error?.takeRetainedValue()).map(String.init(describing:)) ?? "unknown"
                throw KeychainError.secureEnclaveFailed("wrap failed: \(detail)")
            }
            // The blob is useless without the SE key, so the item itself needs no
            // access control — user presence is enforced by the SE key at unwrap.
            try upsertItem(Data([Format.seWrapped.rawValue]) + ciphertext, accessControl: nil)
        } else {
            let access = try userPresenceAccessControl()
            try upsertItem(Data([Format.raw.rawValue]) + masterKeyData, accessControl: access)
        }
    }

    // MARK: - Retrieve

    /// Retrieve the master key as a CryptoKit `SymmetricKey`. Triggers the
    /// biometric / passcode prompt (via the SE key on hardware, via item access
    /// control on the simulator).
    /// - Parameter reason: the LAContext prompt reason shown to the user.
    public static func retrieve(reason: String = "Unlock your Takes") throws -> SymmetricKey {
        let context = LAContext()
        context.localizedReason = reason
        var query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecAttrAccessGroup as String:    accessGroup,
            kSecReturnData as String:         true,
            kSecMatchLimit as String:         kSecMatchLimitOne,
            kSecAttrSynchronizable as String: false
        ]
        query[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw status == errSecItemNotFound ? KeychainError.notFound : KeychainError.retrieveFailed(status)
        }
        guard let payload = item as? Data, payload.count > 1,
              let format = Format(rawValue: payload[payload.startIndex]) else {
            throw KeychainError.malformedStoredKey
        }
        let body = payload.dropFirst()

        switch format {
        case .raw:
            return SymmetricKey(data: body)
        case .seWrapped:
            let privateKey = try fetchSEKey(context: context)
            var error: Unmanaged<CFError>?
            guard let plain = SecKeyCreateDecryptedData(
                privateKey, wrapAlgorithm, Data(body) as CFData, &error
            ) as Data? else {
                let detail = (error?.takeRetainedValue()).map(String.init(describing:)) ?? "unknown"
                throw KeychainError.secureEnclaveFailed("unwrap failed: \(detail)")
            }
            defer {
                // Best-effort zeroization of the intermediate plaintext copy.
                var p = plain
                p.withUnsafeMutableBytes { raw in
                    if let base = raw.baseAddress { memset_s(base, raw.count, 0, raw.count) }
                }
            }
            return SymmetricKey(data: plain)
        }
    }

    /// Whether a master key is stored. `errSecInteractionNotAllowed` means the item
    /// exists but would require user authentication to read — that still counts as
    /// "exists" (previously this returned a false negative for the protected item).
    public static func exists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecMatchLimit as String:      kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    public static func delete() {
        // The wrapped blob…
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
            kSecAttrAccessGroup as String: accessGroup
        ]
        SecItemDelete(query as CFDictionary)
        // …and the Secure Enclave wrapping key (no-op if none exists).
        let keyQuery: [String: Any] = [
            kSecClass as String:              kSecClassKey,
            kSecAttrApplicationTag as String: seKeyTag,
            kSecAttrKeyType as String:        kSecAttrKeyTypeECSECPrimeRandom
        ]
        SecItemDelete(keyQuery as CFDictionary)
    }

    // MARK: - Secure Enclave key management

    private static func userPresenceAccessControl() throws -> SecAccessControl {
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.userPresence],
            nil
        ) else { throw KeychainError.accessControlCreationFailed }
        return access
    }

    private static func fetchOrCreateSEKey() throws -> SecKey {
        if let existing = try? fetchSEKey(context: nil) { return existing }

        // .privateKeyUsage is REQUIRED (and only valid) here: this is a Secure
        // Enclave private key. .userPresence makes every decryption demand
        // Face ID / Touch ID / passcode.
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .userPresence],
            nil
        ) else { throw KeychainError.accessControlCreationFailed }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String:       kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String:       kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String:    true,
                kSecAttrApplicationTag as String: seKeyTag,
                kSecAttrAccessControl as String:  access,
                kSecAttrAccessGroup as String:    accessGroup
            ] as [String: Any]
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let detail = (error?.takeRetainedValue()).map(String.init(describing:)) ?? "unknown"
            throw KeychainError.secureEnclaveFailed("key generation failed: \(detail)")
        }
        return key
    }

    private static func fetchSEKey(context: LAContext?) throws -> SecKey {
        var query: [String: Any] = [
            kSecClass as String:              kSecClassKey,
            kSecAttrApplicationTag as String: seKeyTag,
            kSecAttrKeyType as String:        kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrAccessGroup as String:    accessGroup,
            kSecReturnRef as String:          true
        ]
        if let context { query[kSecUseAuthenticationContext as String] = context }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw status == errSecItemNotFound ? KeychainError.notFound : KeychainError.retrieveFailed(status)
        }
        return (item as! SecKey)
    }

    // MARK: - Item write (update-or-add; never delete-then-add)

    /// `SecItemUpdate` first, falling back to `SecItemAdd` when the item does not
    /// exist. The previous delete-then-add reused the full add dictionary
    /// (including kSecValueData / kSecAttrAccessControl) as a *search* query, which
    /// is invalid on some iOS versions and could brick re-stores with
    /// errSecDuplicateItem; it also had a crash window with no key on disk.
    private static func upsertItem(_ data: Data, accessControl: SecAccessControl?) throws {
        let searchQuery: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecAttrAccessGroup as String:    accessGroup,
            kSecAttrSynchronizable as String: false,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]
        var update: [String: Any] = [kSecValueData as String: data]
        if let accessControl { update[kSecAttrAccessControl as String] = accessControl }

        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            // e.g. errSecInteractionNotAllowed on an access-controlled item: fall
            // back to replacing the item outright with a minimal search query.
            let deleteQuery: [String: Any] = [
                kSecClass as String:           kSecClassGenericPassword,
                kSecAttrService as String:     service,
                kSecAttrAccount as String:     account,
                kSecAttrAccessGroup as String: accessGroup
            ]
            SecItemDelete(deleteQuery as CFDictionary)
            try addItem(data, accessControl: accessControl)
            return
        }
        try addItem(data, accessControl: accessControl)
    }

    private static func addItem(_ data: Data, accessControl: SecAccessControl?) throws {
        var query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecAttrAccessGroup as String:    accessGroup,
            kSecValueData as String:          data,
            kSecAttrSynchronizable as String: false
        ]
        if let accessControl {
            query[kSecAttrAccessControl as String] = accessControl
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.storeFailed(status) }
    }
}
