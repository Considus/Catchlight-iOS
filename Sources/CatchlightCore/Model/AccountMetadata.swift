//
//  AccountMetadata.swift
//  CatchlightCore
//
//  Account metadata (Phase 5 brief §4.8, Encryption Architecture §7).
//
//  Written to `catchlight-account-metadata.json` in the cloud folder. This is the
//  ONLY plaintext file in the cloud folder (besides the advisory lock).
//
//  HISTORY (2026-06-10): the `argon2Salt` field has been REMOVED. It existed for
//  the original Argon2id derivation, which required a random per-account salt
//  recoverable without the device. The current HKDF derivation uses a FIXED
//  domain salt ("catchlight-master-key", see CryptoConstants), so recovery needs
//  only the mnemonic — a per-account salt has no function, and keeping a dead
//  cryptographic parameter in the cross-platform format invited confusion.
//  Decoding ignores the field if present in files written by earlier dev builds.
//

import Foundation

public struct AccountMetadata: Codable, Equatable, Sendable {
    /// Schema version of the account/cloud format. `1` in v1.0.
    public let schemaVersion: Int

    /// ISO 8601 string. Explicit string (not Date) to guarantee a platform-neutral
    /// encoding readable by future web/Android clients.
    public let accountCreatedAt: String

    /// App version that wrote this file, e.g. "1.0.0".
    public let appVersion: String

    public init(schemaVersion: Int, accountCreatedAt: String, appVersion: String) {
        self.schemaVersion = schemaVersion
        self.accountCreatedAt = accountCreatedAt
        self.appVersion = appVersion
    }
}
