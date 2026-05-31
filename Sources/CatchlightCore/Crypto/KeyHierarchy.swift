//
//  KeyHierarchy.swift
//  CatchlightCore
//
//  The HKDF-SHA-256 fan-out from the master key (Encryption Architecture §4,
//  Phase 5 brief §5.3). Every derived key carries a DISTINCT `info` string — the
//  key-separation requirement of the OWASP Key Management Cheat Sheet. A key
//  derived for one purpose can never be repurposed for another, and compromise of
//  one derived key exposes neither the master key nor sibling keys.
//
//  HKDF is correct here (not Argon2id) because the master key is already 256 bits
//  of high entropy; HKDF is the right tool for high-entropy IKM (Encryption
//  Architecture §3 "Why these choices").
//
//      Master Key (32 bytes, from Argon2id, Keychain-only)
//        ├── HKDF info "catchlight-sqlcipher-db-v1"   → DB Key (SQLCipher)
//        ├── HKDF info "catchlight-manifest-hmac-v1"  → Manifest HMAC Key
//        └── HKDF info "catchlight-item-key-v1:<uuid>" → Per-Item Key (never stored)
//

import Foundation
import CryptoKit

public enum KeyInfo {
    public static let databaseKey   = "catchlight-sqlcipher-db-v1"
    public static let manifestHMAC  = "catchlight-manifest-hmac-v1"
    public static let itemKeyPrefix = "catchlight-item-key-v1:"
    public static let deviceHandshake = "catchlight-device-handshake-v1"
}

public struct KeyHierarchy: Sendable {
    public let masterKey: SymmetricKey

    /// - Parameter masterKeyBytes: the 32 raw bytes retrieved from the Keychain.
    public init(masterKeyBytes: Data) {
        self.masterKey = SymmetricKey(data: masterKeyBytes)
    }

    public init(masterKey: SymmetricKey) {
        self.masterKey = masterKey
    }

    /// SQLCipher database key. Derived at every database open; never stored.
    public func databaseKey() -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            info: Data(KeyInfo.databaseKey.utf8),
            outputByteCount: 32
        )
    }

    /// Manifest HMAC key. Signs and verifies `catchlight-manifest.json`.
    public func manifestHMACKey() -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            info: Data(KeyInfo.manifestHMAC.utf8),
            outputByteCount: 32
        )
    }

    /// Per-item key for a specific Take. Re-derived on demand; never stored.
    /// The Take UUID's `uuidString` (uppercase, RFC 4122 canonical form as produced
    /// by `UUID`) is the disambiguating component of the `info` string — this is the
    /// exact form the per-item encryption code uses (Encryption Architecture §10.1).
    public func itemKey(takeUUID: UUID) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            info: Data("\(KeyInfo.itemKeyPrefix)\(takeUUID.uuidString)".utf8),
            outputByteCount: 32
        )
    }

    /// Raw 32-byte representation of the database key, hex-encoded for the SQLCipher
    /// `PRAGMA key = "x'...'"` form. Used by the iOS SQLCipher store.
    public func databaseKeyHex() -> String {
        databaseKey().withUnsafeBytes { raw in
            raw.map { String(format: "%02x", $0) }.joined()
        }
    }
}
