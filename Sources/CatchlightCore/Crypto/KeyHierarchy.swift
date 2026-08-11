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
//  HKDF is correct here because the master key is already 256 bits of high
//  entropy; HKDF is the right tool for high-entropy IKM (Encryption Architecture
//  §3 "Why these choices"). The master key itself is derived from the BIP-39
//  mnemonic by `MasterKeyDerivation` (also HKDF-SHA-256).
//
//      Master Key (32 bytes, from HKDF(mnemonic), Keychain-only)
//        ├── HKDF info "catchlight-sqlcipher-db-v1"  → DB Key (SQLCipher)
//        ├── HKDF info "catchlight-manifest-hmac-v1" → Manifest HMAC Key
//        └── HKDF salt "catchlight-item-key",
//            info <take.uuidString>                  → Per-Item AES-256-GCM key
//                                                     (ephemeral; never stored)
//

import Foundation
import CryptoKit

public enum KeyInfo {
    public static let databaseKey     = "catchlight-sqlcipher-db-v1"
    public static let manifestHMAC    = "catchlight-manifest-hmac-v1"
    public static let deviceHandshake = "catchlight-device-handshake-v1"
    /// Manifest BODY encryption (manifest v3, owner 2026-08-11) — distinct from the HMAC
    /// key above, which authenticates. Separate info strings so the two uses never share
    /// key material, the same discipline the database / handshake keys follow.
    public static let manifestEncryption = "catchlight-manifest-encryption-v1"
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

    /// Manifest BODY encryption key (manifest v3, owner 2026-08-11). Seals the index —
    /// every Take's uuid, its modification time, and the deletion log — which was plain
    /// JSON up to v2, readable by anyone with folder access even though Take CONTENT was
    /// always sealed. Derived, never stored; no new Keychain entry and no change to the
    /// recovery phrase.
    public func manifestEncryptionKey() -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            info: Data(KeyInfo.manifestEncryption.utf8),
            outputByteCount: 32
        )
    }

    /// Per-item AES-256-GCM key for a specific Take. Re-derived on demand; never
    /// stored. Salt + UUID-as-info per Encryption Architecture §10.1; this
    /// delegates to the free function in `TakeCrypto.swift` so the derivation has
    /// exactly one definition.
    public func itemKey(takeUUID: UUID) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            salt: Data(ItemKeyDerivationConstants.salt.utf8),
            // CROSS-PLATFORM CONTRACT: the HKDF info is the UPPERCASE hyphenated
            // UUID string (Apple's `uuidString` is uppercase; many other
            // platforms emit lowercase by default — a lowercase UUID would
            // silently derive a different key). `.uppercased()` is a no-op on
            // Apple platforms but pins the contract explicitly.
            info: Data(takeUUID.uuidString.uppercased().utf8),
            outputByteCount: ItemKeyDerivationConstants.outputByteCount
        )
    }

    /// Hex-encoded form of the database key. Retained for forward compatibility
    /// (and pinned by the EncryptionLayerTests KATs); the current
    /// `EncryptedTakeStore` seals payload columns with per-item keys and does
    /// not consume a whole-database key.
    public func databaseKeyHex() -> String {
        databaseKey().withUnsafeBytes { raw in
            raw.map { String(format: "%02x", $0) }.joined()
        }
    }
}
