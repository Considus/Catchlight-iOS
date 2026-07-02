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
    /// RESERVED — currently never thrown (2026-07-01). Kept for future key-
    /// derivation failure paths; the PIN PBKDF2 it originally described was
    /// removed with the in-app PIN (D-042).
    case kdfFailed(String)
    /// A BIP-39 mnemonic failed checksum/wordlist validation.
    case invalidMnemonic(String)
}

/// Sync and integrity failures.
public enum SyncError: Error, Equatable, Sendable {
    /// The manifest's own HMAC did not verify. The entire inbound batch is
    /// quarantined; the local database is left untouched.
    case manifestSignatureInvalid
    /// RESERVED — currently never thrown (2026-07-01): the pull path reports a
    /// failed per-blob HMAC via `SyncReport.quarantined` instead of throwing.
    case takeIntegrityFailed(UUID)
    /// RESERVED — currently never thrown (2026-07-01): an unreadable declared
    /// blob is reported via `SyncReport.skipped` (provider lag, retried).
    case blobMissing(UUID)
    /// The cloud envelope was structurally invalid (bad version, bad Base64, …).
    case malformedEnvelope(UUID)
    /// A second-device handshake request/response was past its 15-minute expiry.
    case handshakeExpired
    /// No cloud folder is configured — sync was requested in local-only mode.
    case noCloudFolderConfigured
    /// The cloud manifest declares a format version newer than this client
    /// understands. Processed as a hard stop rather than misreading it.
    case unsupportedManifestVersion(Int)
}

/// Local storage failures.
public enum StorageError: Error, Equatable, Sendable {
    case openFailed(String)
    case notFound(UUID)
    case writeFailed(String)
    /// Attempt to designate a second Obie without resolving the existing one.
    case obieConflict(existing: UUID)
    /// A stored row could not be decoded (unparseable id/date, undecryptable or
    /// corrupt payload). Surfaced loudly — silently fabricating replacement
    /// values (a fresh UUID, "now") would mutate the item's identity, break the
    /// per-item key derivation, and corrupt sync matching.
    case corruptRow(String)
}
