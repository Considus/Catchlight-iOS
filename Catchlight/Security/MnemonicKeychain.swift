//
//  MnemonicKeychain.swift
//  Catchlight (iOS app target) — Task 3.12
//
//  Persistent storage for the 12-word BIP-39 privacy phrase, so Settings →
//  Privacy phrase can re-display it after onboarding. Stored as the canonical
//  space-joined word list under `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`,
//  non-synchronisable, scoped to the same access group as the master key.
//
//  SECURITY (revised 2026-06-10): the phrase is the ROOT secret — it can
//  re-derive the master key on any device, forever. It therefore now carries
//  `.userPresence` access control: reading it demands Face ID / Touch ID /
//  device passcode via the system sheet, in addition to the app-level PIN gate
//  enforced by PrivacyPhraseView. Previously it was the most powerful secret
//  with the weakest posture (silently readable by any code in the access group
//  whenever the device was unlocked).
//
//  TEST SEAM: unit tests cannot answer a user-presence prompt and must never
//  touch the production phrase slot (deleting it would be unrecoverable for a
//  real user). `Configuration` lets tests redirect to a throwaway service name
//  and disable user presence; production code never changes these defaults.
//

import Foundation
import Security
import LocalAuthentication

public enum MnemonicKeychain {

    public struct Configuration {
        public var service = KeychainConfig.service
        public var account = "privacy-phrase"
        public var accessGroup = KeychainConfig.accessGroup
        /// Production: true. Tests set false (a user-presence item cannot be
        /// read headlessly, and the simulator may have no enrolled biometrics).
        public var requireUserPresence = true
        public init() {}
    }

    /// Overridden by unit tests only.
    public static var configuration = Configuration()

    /// Store (or replace) the 12-word mnemonic. Joined with single spaces — the
    /// canonical BIP-39 representation.
    public static func store(_ words: [String]) throws {
        let joined = words.joined(separator: " ")
        let data = Data(joined.utf8)

        // Replace-then-add with a minimal search query (kSecValueData and
        // accessibility attributes are not valid search keys).
        delete()

        var query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        configuration.service,
            kSecAttrAccount as String:        configuration.account,
            kSecAttrAccessGroup as String:    configuration.accessGroup,
            kSecValueData as String:          data,
            kSecAttrSynchronizable as String: false
        ]
        if configuration.requireUserPresence {
            guard let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.userPresence],
                nil
            ) else { throw KeychainError.accessControlCreationFailed }
            query[kSecAttrAccessControl as String] = access
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.storeFailed(status) }
    }

    /// Retrieve the stored mnemonic, or nil if none has ever been persisted (or
    /// the user cancelled / failed the user-presence prompt).
    /// - Parameter reason: shown on the system authentication sheet.
    public static func retrieve(reason: String = "Reveal your privacy phrase") -> [String]? {
        var query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        configuration.service,
            kSecAttrAccount as String:        configuration.account,
            kSecAttrAccessGroup as String:    configuration.accessGroup,
            kSecReturnData as String:         true,
            kSecMatchLimit as String:         kSecMatchLimitOne,
            kSecAttrSynchronizable as String: false
        ]
        if configuration.requireUserPresence {
            let context = LAContext()
            context.localizedReason = reason
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let joined = String(data: data, encoding: .utf8) else {
            return nil
        }
        let words = joined.split(separator: " ").map(String.init)
        return words.isEmpty ? nil : words
    }

    /// Whether a phrase is stored, WITHOUT triggering the user-presence prompt.
    /// `errSecInteractionNotAllowed` means the item exists but needs auth.
    public static func exists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        configuration.service,
            kSecAttrAccount as String:        configuration.account,
            kSecAttrAccessGroup as String:    configuration.accessGroup,
            kSecMatchLimit as String:         kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    public static func delete() {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     configuration.service,
            kSecAttrAccount as String:     configuration.account,
            kSecAttrAccessGroup as String: configuration.accessGroup
        ]
        SecItemDelete(query as CFDictionary)
    }
}
