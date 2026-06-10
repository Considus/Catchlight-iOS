//
//  MnemonicKeychain.swift
//  Catchlight (iOS app target) — Task 3.12
//
//  Persistent storage for the 12-word BIP-39 privacy phrase, so Settings →
//  Privacy phrase can re-display it after onboarding. Stored as the canonical
//  space-joined word list under `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`,
//  non-synchronisable, scoped to the same access group as the master key.
//
//  SECURITY NOTE: this slightly weakens "shown once at setup" — anyone who can
//  unlock the device AND get past the Privacy-phrase row's PIN gate can read
//  the phrase. The PIN gate is enforced by the calling view (see
//  PrivacyPhraseView). The Keychain item itself does NOT carry `.userPresence`
//  because we want to gate on the app's PIN, not the device passcode, and
//  the storage must remain readable when SettingsView is already open.
//

import Foundation
import Security

public enum MnemonicKeychain {

    private static let service = "com.considus.catchlight"
    private static let account = "privacy-phrase"
    private static let accessGroup = "YTPP9HU9F9.com.considus.catchlight"

    /// Store (or replace) the 12-word mnemonic. Joined with single spaces — the
    /// canonical BIP-39 representation.
    public static func store(_ words: [String]) throws {
        let joined = words.joined(separator: " ")
        guard let data = joined.data(using: .utf8) else {
            throw KeychainError.storeFailed(errSecParam)
        }
        let query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecAttrAccessGroup as String:    accessGroup,
            kSecValueData as String:          data,
            kSecAttrAccessible as String:     kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.storeFailed(status) }
    }

    /// Retrieve the stored mnemonic, or nil if none has ever been persisted.
    public static func retrieve() -> [String]? {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecAttrAccessGroup as String:    accessGroup,
            kSecReturnData as String:         true,
            kSecMatchLimit as String:         kSecMatchLimitOne,
            kSecAttrSynchronizable as String: false
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let joined = String(data: data, encoding: .utf8) else {
            return nil
        }
        let words = joined.split(separator: " ").map(String.init)
        return words.isEmpty ? nil : words
    }

    public static func exists() -> Bool { retrieve() != nil }

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
