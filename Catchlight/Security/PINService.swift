//
//  PINService.swift
//  Catchlight (iOS app target)
//
//  Local PIN / biometric app lock (Encryption Architecture §13).
//
//  IMPORTANT SCOPE: the PIN protects APP ACCESS on this device only — it is NOT
//  part of the encryption key chain. Data confidentiality is provided by the
//  Keychain-stored master key (HKDF-derived from the BIP-39 mnemonic) and the
//  per-item AES-256-GCM encryption of Take content at rest. Losing the PIN does
//  not lose data; recovery is via the mnemonic.
//
//  KDF CHOICE: the PIN is low-entropy (6+ characters/digits) and therefore
//  requires a slow KDF to resist on-device offline brute force. Apple-native
//  PBKDF2-HMAC-SHA-256 via CommonCrypto is the right tool here — slower than
//  Argon2id, but Argon2id is no longer available in the codebase and PBKDF2 is
//  acceptable for protecting UI access (NOT for key derivation).
//
//  Policy (Encryption Architecture §13.3, revised 2026-06-10):
//    • Minimum 6 alphanumeric characters OR a 6-digit numeric PIN. Sub-6 PINs
//      are rejected. The 10-attempt lockout is the primary defence against
//      brute force at this entropy floor.
//    • After 10 consecutive failed attempts the app locks and requires the mnemonic.
//    • The failed-attempt counter is PERSISTED in the Keychain (2026-06-10): an
//      in-memory counter could be reset by force-quitting the app, which made the
//      lockout — the primary brute-force defence — trivially bypassable. `verify`
//      also refuses attempts itself once locked out, rather than trusting callers.
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
    private let service: String
    private let hashAccount = "pin-hash"
    private let saltAccount = "pin-salt"
    private let attemptsAccount = "pin-failed-attempts"
    // Resolved keychain access group — see KeychainConfig for why the literal
    // `"$(AppIdentifierPrefix)…"` form cannot be used in Swift source.
    // Optional: tests pass nil so items live in the host app's default group
    // (an EXPLICIT group requires the keychain-sharing entitlement, which
    // unsigned simulator test hosts lack — SecItemAdd fails with -34018).
    private let accessGroup: String?

    /// PBKDF2 parameters. 600_000 iterations matches OWASP 2023 guidance for
    /// PBKDF2-HMAC-SHA-256. 32-byte output.
    private static let pbkdf2Iterations: UInt32 = 600_000
    private static let pbkdf2OutputLength: Int = 32

    /// Production storage slots by default. Tests pass a distinct `service` so
    /// they can never clobber a real user's PIN (the suites previously called
    /// `reset()` against the production slots).
    public init(service: String = KeychainConfig.service,
                accessGroup: String? = KeychainConfig.accessGroup) {
        self.service = service
        self.accessGroup = accessGroup
    }

    /// Set or change the PIN. Generates a fresh random salt.
    public func setPIN(_ pin: String) throws {
        if let reason = PINPolicy.rejectionReason(for: pin) {
            throw CryptoError.kdfFailed(reason)
        }
        let salt = SecureRandom.bytes(16)
        let hash = try Self.pbkdf2(password: pin, salt: salt)
        try storeItem(hash, account: hashAccount)
        try storeItem(salt, account: saltAccount)
        persistFailedAttempts(0)
    }

    /// Verify a PIN attempt. Returns true on success; increments the persisted
    /// failure counter on mismatch. Once `failedAttempts` reaches
    /// `PINPolicy.maxFailedAttempts` this method refuses further attempts
    /// (returns false without evaluating) until the PIN is reset via mnemonic
    /// recovery — enforcement no longer relies on the caller checking first.
    public func verify(_ pin: String) throws -> Bool {
        guard !isLockedOut else { return false }
        guard let storedHash = readItem(account: hashAccount),
              let salt = readItem(account: saltAccount) else {
            throw KeychainError.notFound
        }
        let candidate = try Self.pbkdf2(password: pin, salt: salt)
        // Constant-time comparison.
        let match = constantTimeEqual(candidate, storedHash)
        persistFailedAttempts(match ? 0 : failedAttempts + 1)
        return match
    }

    /// Consecutive failed attempts, persisted in the Keychain so the lockout
    /// survives app relaunches and reinstalls within the same keychain lifetime.
    public var failedAttempts: Int {
        guard let data = readItem(account: attemptsAccount), data.count == 1 else { return 0 }
        return Int(data[data.startIndex])
    }

    public var isLockedOut: Bool { failedAttempts >= PINPolicy.maxFailedAttempts }

    public func reset() {
        deleteItem(account: hashAccount)
        deleteItem(account: saltAccount)
        deleteItem(account: attemptsAccount)
    }

    private func persistFailedAttempts(_ count: Int) {
        let clamped = UInt8(clamping: count)
        try? storeItem(Data([clamped]), account: attemptsAccount)
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
        // Update-or-add. The previous delete-then-add reused the full add
        // dictionary (including kSecValueData / kSecAttrAccessible) as a search
        // query, which is not a valid search shape on all iOS versions and could
        // leave a stale item behind, failing the subsequent add with
        // errSecDuplicateItem.
        var searchQuery: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecAttrSynchronizable as String: false
        ]
        if let accessGroup { searchQuery[kSecAttrAccessGroup as String] = accessGroup }
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        // Any other update failure (not just errSecItemNotFound) falls back to
        // replace-then-add: e.g. unsigned simulator test hosts report
        // errSecMissingEntitlement (-34018) from SecItemUpdate while SecItemAdd
        // succeeds. The delete uses the minimal search query.
        if updateStatus != errSecItemNotFound {
            SecItemDelete(searchQuery as CFDictionary)
        }
        var addQuery: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecValueData as String:          data,
            kSecAttrAccessible as String:     kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
        if let accessGroup { addQuery[kSecAttrAccessGroup as String] = accessGroup }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.storeFailed(status) }
    }

    private func readItem(account: String) -> Data? {
        var query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecReturnData as String:         true,
            kSecMatchLimit as String:         kSecMatchLimitOne,
            kSecAttrSynchronizable as String: false
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func deleteItem(account: String) {
        var query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        SecItemDelete(query as CFDictionary)
    }

    private func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}
