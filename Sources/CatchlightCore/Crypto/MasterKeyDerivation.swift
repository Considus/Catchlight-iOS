//
//  MasterKeyDerivation.swift
//  CatchlightCore
//
//  Master key derivation from the BIP-39 mnemonic via HKDF-SHA-256 (CryptoKit).
//
//  WHY HKDF, NOT ARGON2ID: the BIP-39 mnemonic already carries 128 bits of
//  entropy. Memory-hard / slow KDFs (Argon2id, scrypt) exist to harden LOW-entropy
//  secrets (PINs, passwords) against offline brute force. For a high-entropy
//  secret like a 12-word mnemonic, HKDF is the correct extract-and-expand KDF.
//  See Encryption Specialist review 2026-06-05.
//
//  Cross-platform contract: every client must produce identical 32 bytes from
//  the same mnemonic. The mnemonic is canonicalised to lowercase, NFD-normalised
//  (decomposedStringWithCanonicalMapping), single-space-joined UTF-8 — exactly
//  the form used by the previous Argon2id derivation, preserving the on-the-wire
//  input shape across the family of
//  Catchlight clients.
//

import Foundation
import CryptoKit

public enum MasterKeyDerivation {

    /// Derive the 32-byte Catchlight master key from a 12-word BIP-39 mnemonic.
    public static func derive(from mnemonic: [String]) -> SymmetricKey {
        let normalised = mnemonic
            .map { $0.lowercased() }
            .joined(separator: " ")
        let ikm = SymmetricKey(data: Data(normalised.decomposedStringWithCanonicalMapping.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: Data(MasterKeyDerivationConstants.salt.utf8),
            info: Data(MasterKeyDerivationConstants.info.utf8),
            outputByteCount: MasterKeyDerivationConstants.outputByteCount
        )
    }

    /// Convenience: derived master key as raw bytes, for Keychain storage.
    public static func deriveRaw(from mnemonic: [String]) -> Data {
        derive(from: mnemonic).withUnsafeBytes { Data($0) }
    }
}
