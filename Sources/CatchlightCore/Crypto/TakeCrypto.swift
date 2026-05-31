//
//  TakeCrypto.swift
//  CatchlightCore
//
//  Per-item Take encryption (Encryption Architecture §10, Phase 5 brief §5.4).
//
//  Each Take is sealed with ChaCha20-Poly1305 under a key unique to that Take,
//  derived on demand from the master key via HKDF (KeyHierarchy.itemKey). The key
//  is never stored. CryptoKit generates a fresh random 12-byte nonce per `seal`
//  and embeds it in `combined` — nonces are NEVER generated or reused manually.
//
//  The low-level `encryptTake` / `decryptTake` functions are reproduced verbatim
//  from the brief §5.4 so the implementation matches the authoritative spec
//  exactly. `TakeCrypto` wraps them with the payload (Take ⇄ JSON ⇄ ciphertext)
//  serialisation step.
//

import Foundation
import CryptoKit

// MARK: - Verbatim spec functions (Phase 5 brief §5.4 / Encryption Architecture §10)

public func itemKey(masterKey: SymmetricKey, takeUUID: UUID) -> SymmetricKey {
    return HKDF<SHA256>.deriveKey(
        inputKeyMaterial: masterKey,
        info: Data("catchlight-item-key-v1:\(takeUUID.uuidString)".utf8),
        outputByteCount: 32
    )
}

public func encryptTake(_ plaintext: Data, masterKey: SymmetricKey, takeUUID: UUID) throws -> Data {
    let key = itemKey(masterKey: masterKey, takeUUID: takeUUID)
    let sealedBox = try ChaChaPoly.seal(plaintext, using: key)
    return sealedBox.combined  // nonce (12 bytes) + ciphertext + tag (16 bytes)
}

public func decryptTake(_ combined: Data, masterKey: SymmetricKey, takeUUID: UUID) throws -> Data {
    let key = itemKey(masterKey: masterKey, takeUUID: takeUUID)
    do {
        let sealedBox = try ChaChaPoly.SealedBox(combined: combined)
        return try ChaChaPoly.open(sealedBox, using: key)
    } catch CryptoKitError.incorrectParameterSize {
        throw CryptoError.malformedCiphertext
    } catch {
        // Any open() failure is an AEAD tag failure: tampering, corruption, or
        // wrong key. The plaintext is never returned.
        throw CryptoError.authenticationFailed
    }
}

// MARK: - Payload-level wrapper

/// Encrypts and decrypts whole `Take` values: Take ⇄ platform-agnostic JSON ⇄
/// ChaCha20-Poly1305 ciphertext. The entire payload is encrypted (body text, all
/// type flags, reminder, completion, checklist, attachments, timestamps, sequence
/// membership) — everything except the Take's `id`, which is the HKDF `info` input
/// and must be known before decryption (Encryption Architecture §10.5).
public struct TakeCrypto: Sendable {
    private let keys: KeyHierarchy

    public init(keys: KeyHierarchy) {
        self.keys = keys
    }

    /// Serialise the Take to platform-agnostic JSON, then seal it.
    /// Returns the ChaCha20-Poly1305 combined form (nonce + ciphertext + tag).
    public func seal(_ take: Take) throws -> Data {
        let plaintext = try PlatformJSON.encode(take)
        return try encryptTake(plaintext, masterKey: keys.masterKey, takeUUID: take.id)
    }

    /// Open a sealed blob for a known Take UUID and decode it back to a Take.
    /// - Throws: `CryptoError.authenticationFailed` if the blob was tampered with.
    public func open(_ combined: Data, takeUUID: UUID) throws -> Take {
        let plaintext = try decryptTake(combined, masterKey: keys.masterKey, takeUUID: takeUUID)
        return try PlatformJSON.decode(Take.self, from: plaintext)
    }
}
