//
//  CryptoConstants.swift
//  CatchlightCore
//
//  Fixed domain-separation strings for master-key derivation. These bytes are
//  part of the cross-platform reproducibility contract: every Catchlight client
//  (iOS, future Web/Android/macOS) must use the IDENTICAL salt and info bytes,
//  otherwise the same mnemonic will derive different master keys and recovery
//  silently breaks. Do not alter post-release.
//

import Foundation

public enum MasterKeyDerivationConstants {
    /// Fixed domain salt for HKDF master-key derivation. NOT secret. The mnemonic
    /// is the entropy source; a random per-account salt is unnecessary and would
    /// only obstruct recovery across devices.
    public static let salt = "catchlight-master-key"

    /// HKDF `info` (purpose label) for the master key.
    public static let info = "master-key"

    /// 256-bit master key.
    public static let outputByteCount = 32
}

/// Domain-separation strings for per-item (per-Take) key derivation.
///
///     itemKey = HKDF<SHA256>(
///         IKM  = masterKey,
///         salt = "catchlight-item-key",
///         info = <take.id.uuidString>,
///         L    = 32
///     )
///
/// The per-item key is ephemeral — derived on demand, used once, then dropped.
/// It is NEVER persisted. AES-256-GCM (CryptoKit `AES.GCM`) is the AEAD used to
/// seal Take payloads under this key.
public enum ItemKeyDerivationConstants {
    /// Fixed domain salt for per-item HKDF derivation. NOT secret.
    public static let salt = "catchlight-item-key"

    /// 256-bit per-item key.
    public static let outputByteCount = 32
}
