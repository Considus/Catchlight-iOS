//
//  PINService.swift
//  Catchlight (iOS app target)
//
//  Local PIN / biometric app lock (Encryption Architecture §13).
//
//  IMPORTANT SCOPE: the PIN protects APP ACCESS on this device only — it is NOT
//  part of the encryption key chain. Data confidentiality is provided by the
//  Keychain-stored master key (HKDF-derived from the BIP-39 mnemonic) and by
//  SQLCipher. Losing the PIN does not lose data; recovery is via the mnemonic.
//
//  KDF CHOICE: the PIN is low-entropy (6+ alphanumeric or 8+ digit) and therefore
//  requires a slow KDF to resist on-device offline brute force. Apple-native
//  PBKDF2-HMAC-SHA-256 via CommonCrypto is the right tool here — slower than
//  Argon2id, but Argon2id is no longer available in the codebase and PBKDF2 is
//  acceptable for protecting UI access (NOT for key derivation).
//
//  Policy:
//    • Minimum 6 alphanumeric characters OR a 6-digit numeric PIN. Sub-6 PINs
//      are rejected. The 10-attempt lockout is the primary defence against
//      brute force at this entropy floor.
//    • After 10 consecutive failed attempts the app locks and requires the mnemonic.
//

import Foundation
import Security
import CommonCrypto
import CatchlightCore

public struct PINPolicy {
    public static let maxFailedAttempts = 10

    /// Returns nil if acceptable, otherwise a human-readable reason.
    public static func rejectionReason(for pin: String) -> String? {
        let digitsOnly = pin.allSatisfy { $0.isNumber }
        if digitsOnly {
            if pin.count < 6 { return "Numeric passcodes must be at least 6 digits." }
        } else {
            if pin.count < 6 { return "Passcodes must be at least 6 characters." }
        }
        return nil
    }
}

public final class PINService {
    private let service = "com.considus.catchlight"
    private let hashAccount = "pin-hash"
    private let saltAccount = "pin-salt"
    // Must match the RESOLVED entitlement string in the signed binary. See the
    // long comment in `MasterKeyKeychain.accessGroup` — the literal
    // `"$(AppIdentifierPrefix)…"` form is only substituted in plist/entitlements
    // files, never in Swift, and using it here returns -34018 at runtime.
    // Team prefix YTPP9HU9F9 = Mark Stradling (project.yml DEVELOPMENT_TEAM).
    private let accessGroup = "YTPP9HU9F9.com.considus.catchlight"

    /// PBKDF2 parameters. 600_000 iterations matches OWASP 2023 guidance for
    /// PBKDF2-HMAC-SHA-256. 32-byte output.
    private static let pbkdf2Iterations: UInt32 = 600_000
    private static let pbkdf2OutputLength: Int = 32

    public private(set) var failedAttempts = 0

    public init() {}

    /// Set or change the PIN. Generates a fresh random salt.
    public func setPIN(_ pin: String) throws {
        if let reason = PINPolicy.rejectionReason(for: pin) {
            throw CryptoError.kdfFailed(reason)
        }
        let salt = SecureRandom.bytes(16)
        let hash = try Self.pbkdf2(password: pin, salt: salt)
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
        let candidate = try Self.pbkdf2(password: pin, salt: salt)
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

    // MARK: - PBKDF2 (Apple-native via CommonCrypto)

    private static func pbkdf2(password: String, salt: Data) throws -> Data {
        let pwBytes = Array(password.utf8)
        var output = Data(count: pbkdf2OutputLength)
        let status = output.withUnsafeMutableBytes { outRaw -> Int32 in
            guard let outPtr = outRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return Int32(kCCParamError)
            }
            return salt.withUnsafeBytes { saltRaw -> Int32 in
                let saltPtr = saltRaw.baseAddress?.assumingMemoryBound(to: UInt8.self)
                return CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwBytes, pwBytes.count,
                    saltPtr, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    pbkdf2Iterations,
                    outPtr, pbkdf2OutputLength
                )
            }
        }
        guard status == kCCSuccess else {
            throw CryptoError.kdfFailed("CCKeyDerivationPBKDF returned \(status)")
        }
        return output
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
