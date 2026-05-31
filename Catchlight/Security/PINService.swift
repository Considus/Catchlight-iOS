//
//  PINService.swift
//  Catchlight (iOS app target)
//
//  Local PIN / biometric app lock (Encryption Architecture §13, Phase 5 brief §5.10).
//
//  The PIN locks the APP on this device. It is INDEPENDENT of the mnemonic →
//  master-key derivation — losing the PIN does not lose data (recover via mnemonic).
//  The PIN itself is never stored; only Argon2id(PIN, pin_salt) is kept in the
//  Keychain (WhenUnlockedThisDeviceOnly, non-synchronisable). The PIN salt is a
//  DIFFERENT random value from the master-key Argon2id salt.
//
//  Policy:
//    • Minimum 6 alphanumeric characters OR an 8-digit numeric PIN. 4-digit PINs
//      are rejected.
//    • After 10 consecutive failed attempts the app locks and requires the mnemonic.
//

import Foundation
import Security
import CryptoKit
import CatchlightCore

public struct PINPolicy {
    public static let maxFailedAttempts = 10

    /// Returns nil if acceptable, otherwise a human-readable reason.
    public static func rejectionReason(for pin: String) -> String? {
        let digitsOnly = pin.allSatisfy { $0.isNumber }
        if digitsOnly {
            if pin.count < 8 { return "Numeric passcodes must be at least 8 digits." }
        } else {
            if pin.count < 6 { return "Passcodes must be at least 6 characters." }
        }
        return nil
    }
}

public final class PINService {
    private let kdf: Argon2idDeriving
    private let service = "com.considus.catchlight"
    private let hashAccount = "pin-hash"
    private let saltAccount = "pin-salt"
    private let accessGroup = "$(AppIdentifierPrefix)com.considus.catchlight"

    /// PIN hashing uses the same Argon2id cost as the master key; the security
    /// requirement is identical (resist offline brute force of a low-entropy secret).
    private let params = Argon2Parameters.catchlightMasterKey

    public private(set) var failedAttempts = 0

    public init(kdf: Argon2idDeriving) { self.kdf = kdf }

    /// Set or change the PIN. Generates a fresh random salt distinct from the
    /// master-key salt.
    public func setPIN(_ pin: String) throws {
        if let reason = PINPolicy.rejectionReason(for: pin) {
            throw CryptoError.kdfFailed(reason)
        }
        let salt = SecureRandom.bytes(16)
        let hash = try kdf.deriveKey(passwordBytes: Array(pin.utf8), saltBytes: Array(salt), parameters: params)
        try storeItem(hash, account: hashAccount)
        try storeItem(salt, account: saltAccount)
        failedAttempts = 0
    }

    /// Verify a PIN attempt. Returns true on success; increments the failure counter
    /// on mismatch. Caller must lock to mnemonic recovery once `failedAttempts`
    /// reaches `PINPolicy.maxFailedAttempts`.
    public func verify(_ pin: String) throws -> Bool {
        guard let storedHash = readItem(account: hashAccount),
              let salt = readItem(account: saltAccount) else {
            throw KeychainError.notFound
        }
        let candidate = try kdf.deriveKey(passwordBytes: Array(pin.utf8), saltBytes: Array(salt), parameters: params)
        // Constant-time comparison.
        let match = constantTimeEqual(candidate, storedHash)
        if match { failedAttempts = 0 } else { failedAttempts += 1 }
        return match
    }

    public var isLockedOut: Bool { failedAttempts >= PINPolicy.maxFailedAttempts }

    public func reset() {
        deleteItem(account: hashAccount)
        deleteItem(account: saltAccount)
        failedAttempts = 0
    }

    // MARK: - Keychain helpers (WhenUnlockedThisDeviceOnly, non-synchronisable)

    private func storeItem(_ data: Data, account: String) throws {
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

    private func readItem(account: String) -> Data? {
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
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func deleteItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
            kSecAttrAccessGroup as String: accessGroup
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}
