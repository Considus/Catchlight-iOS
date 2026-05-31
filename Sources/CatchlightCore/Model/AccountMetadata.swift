//
//  AccountMetadata.swift
//  CatchlightCore
//
//  Account metadata (Phase 5 brief §4.8, Encryption Architecture §7).
//
//  Written to `catchlight-account-metadata.json` in the cloud folder. This is the
//  ONLY plaintext file in the cloud folder. It exists for account recovery: the
//  Argon2id salt cannot be derived from the mnemonic, so it must be recoverable
//  without the device. The salt is NOT secret — Argon2id's security does not
//  depend on salt secrecy; the salt prevents cross-user precomputation only
//  (Encryption Architecture §7).
//

import Foundation

public struct AccountMetadata: Codable, Equatable, Sendable {
    /// Schema version of the account/cloud format. `1` in v1.0.
    public let schemaVersion: Int

    /// ISO 8601 string. Explicit string (not Date) to guarantee a platform-neutral
    /// encoding readable by future web/Android clients.
    public let accountCreatedAt: String

    /// Base64-encoded Argon2id salt used for mnemonic → master-key derivation.
    /// Not secret. Required for account recovery on a device with no Keychain entry.
    public let argon2Salt: String

    /// App version that wrote this file, e.g. "1.0.0".
    public let appVersion: String

    public init(schemaVersion: Int, accountCreatedAt: String, argon2Salt: String, appVersion: String) {
        self.schemaVersion = schemaVersion
        self.accountCreatedAt = accountCreatedAt
        self.argon2Salt = argon2Salt
        self.appVersion = appVersion
    }
}
