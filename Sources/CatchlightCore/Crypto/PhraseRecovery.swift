//
//  PhraseRecovery.swift
//  CatchlightCore
//
//  Recovering an EXISTING identity from a user-entered privacy phrase — the crypto core of
//  cross-device migration/restore (Recovery & Migration design v1.0, chunk 1). This is the
//  single, enforced "validate BEFORE deriving" seam: `BIP39.validate` throws on a wrong word
//  count, a word outside the list, or a bad checksum, so no caller can turn an arbitrary or
//  mistyped phrase into a key. Only a well-formed BIP-39 mnemonic reaches
//  `MasterKeyDerivation`.
//
//  The derived key is IDENTICAL to the one the generate path (`OnboardingViewModel
//  .finishOnboarding`) stores for the same words — derivation is deterministic HKDF with a
//  fixed domain salt/info, no per-device randomness — which is exactly what lets a second
//  device decrypt the same cloud data. Whether the phrase is the RIGHT one for a particular
//  cloud folder is a SEPARATE check, proven by the manifest HMAC at sync time, not here.
//

import Foundation

public enum PhraseRecovery {

    /// Validate a user-entered mnemonic and derive the raw 32-byte master key, or throw
    /// `CryptoError.invalidMnemonic`. Each word is trimmed of surrounding whitespace and empty
    /// tokens are dropped, so a stray space can't fail an otherwise-correct phrase; casing and
    /// NFD-normalisation are handled downstream by validation and derivation.
    public static func recoverMasterKey(from words: [String], bip39: BIP39) throws -> Data {
        let cleaned = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        try bip39.validate(mnemonic: cleaned)          // throws on bad count / unknown word / checksum
        return MasterKeyDerivation.deriveRaw(from: cleaned)
    }
}
