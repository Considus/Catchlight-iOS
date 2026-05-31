//
//  Errors.swift
//  CatchlightCore
//
//  The error taxonomy. The architecture document (§6, error handling strategy)
//  groups failures into three families: cryptographic, sync/integrity, and
//  storage. Cryptographic failures are NEVER silently swallowed — a failed AEAD
//  tag means tampering or corruption and must surface (quarantine + user alert),
//  never "best effort decrypt".
//

import Foundation

/// Cryptographic failures. Any of these is treated as a hard failure for the item
/// involved — there is no partial or "best effort" decryption.
public enum CryptoError: Error, Equatable, Sendable {
    /// AEAD authentication tag did not verify: ciphertext was tampered with or
    /// corrupted, or the wrong key was used. The plaintext is never returned.
    case authenticationFailed
    /// Ciphertext was malformed (e.g. too short to contain nonce + tag).
    case malformedCiphertext
    /// Argon2id derivation failed at the C boundary (out of memory, bad params).
    case kdfFailed(String)
    /// A BIP-39 mnemonic failed checksum/wordlist validation.
    case invalidMnemonic(String)
}

/// Sync and integrity failures.
public enum SyncError: Error, Equatable, Sendable {
    /// The manifest's own HMAC did not verify. The entire inbound batch is
    /// quarantined; the local database is left untouched.
    case manifestSignatureInvalid
    /// A specific Take blob's HMAC did not verify. That one Take is quarantined;
    /// the rest of the sync continues.
    case takeIntegrityFailed(UUID)
    /// A blob declared in the manifest could not be read from the cloud folder.
    case blobMissing(UUID)
    /// The cloud envelope was structurally invalid (bad version, bad Base64, …).
    case malformedEnvelope(UUID)
    /// A second-device handshake request/response was past its 15-minute expiry.
    case handshakeExpired
    /// No cloud folder is configured — sync was requested in local-only mode.
    case noCloudFolderConfigured
}

/// Local storage failures.
public enum StorageError: Error, Equatable, Sendable {
    case openFailed(String)
    case notFound(UUID)
    case writeFailed(String)
    /// Attempt to designate a second Obie without resolving the existing one.
    case obieConflict(existing: UUID)
}
