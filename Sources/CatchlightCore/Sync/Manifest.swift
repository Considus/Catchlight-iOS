//
//  Manifest.swift
//  CatchlightCore
//
//  The cloud-folder manifest (Encryption Architecture §11, Phase 5 brief §7.3).
//  `catchlight-manifest.json` is an HMAC-signed index of every synced Take. On
//  inbound sync the manifest signature is verified FIRST; then each downloaded
//  blob is verified against its per-entry HMAC before any decryption is attempted.
//
//  v3 (owner 2026-08-11, D-196) — THE BODY IS NOW ENCRYPTED. What is on disk:
//
//      {
//        "version": 3,
//        "encryptedBody": "<Base64 nonce+ciphertext+tag>",
//        "manifestHmac": "<hex HMAC of the envelope body>"
//      }
//
//  and the sealed body inside it is the same index as before:
//
//      {
//        "version": 3,
//        "updated": "2026-05-28T07:00:00.000Z",
//        "schemaVersion": 1,
//        "takes": [
//          { "uuid": "...", "modified": "...", "hmac": "<hex HMAC of the .clk blob>" }
//        ],
//        "tombstones": [ { "uuid": "...", "deletedAt": "..." } ]
//      }
//
//  WHY. Up to v2 that index sat in the cloud folder as readable JSON. It was signed,
//  so it could not be tampered with — but signing is not encryption. Anyone with
//  folder access could read every Take's uuid, its last-modified time to the
//  millisecond, and a 180-day record of what had been deleted and when: a complete
//  log of when the user worked and what they threw away, even though no Take's
//  CONTENT was ever readable.
//
//  Not hidden, and the privacy policy must not claim otherwise: the number of files,
//  their sizes, and the cloud provider's own file timestamps. Those are properties of
//  putting files in someone else's folder, not of this format.
//
//  The `manifestHmac` field is computed over the envelope with the field set to empty,
//  then filled in — so verification recomputes over the same canonical body. Because
//  PlatformJSON uses `.sortedKeys`, it serialises deterministically. v1/v2 plaintext
//  manifests are still READ (a folder written by an earlier build keeps syncing) but are
//  never written: the next push rewrites the folder as v3.
//

import Foundation
import CryptoKit

public struct ManifestEntry: Codable, Equatable, Sendable {
    public let uuid: UUID
    public let modified: String        // ISO-8601
    public let hmac: String            // hex-encoded HMAC-SHA-256 of the .clk blob bytes

    public init(uuid: UUID, modified: String, hmac: String) {
        self.uuid = uuid
        self.modified = modified
        self.hmac = hmac
    }
}

/// A deletion record in the manifest (manifest v2, 2026-06-10). Deletions are
/// PROPAGATED explicitly instead of being inferred from absence — inference
/// caused deleted Takes to be resurrected by the next pull, and made transient
/// blob-read failures cascade into fleet-wide deletions.
public struct ManifestTombstone: Codable, Equatable, Sendable {
    public let uuid: UUID
    public let deletedAt: String       // ISO-8601

    public init(uuid: UUID, deletedAt: String) {
        self.uuid = uuid
        self.deletedAt = deletedAt
    }
}

/// The v3 on-disk form of `catchlight-manifest.json` — an ENCRYPTED envelope (owner
/// 2026-08-11, D-196).
///
/// Up to v2 the manifest was plain JSON. It was HMAC-signed, so nobody could tamper with
/// it, but signing is not encryption: anyone with folder access — the cloud provider, a
/// stale backup, a disclosure request — could read every Take's uuid, its last-modified
/// time to the millisecond, and a 180-day log of what had been deleted and when. Not what
/// any Take SAID, but a complete record of when the user worked and what they threw away.
///
/// `version` and `manifestHmac` stay OUTSIDE the ciphertext, deliberately:
///   • `version` must be readable WITHOUT the key, or a client cannot tell a v2 manifest
///     from a v3 one and the fail-closed version gate becomes unreachable.
///   • `manifestHmac` keeps `SyncEngine`'s "verify the signature FIRST, quarantine
///     everything on failure" flow working unchanged. AES-GCM's tag already authenticates
///     the body, so this is belt-and-braces — but it means the pull path did not have to be
///     restructured around a new failure mode.
///
/// What this does NOT hide, and the privacy policy must not claim it does: the number of
/// files, their sizes, and the provider's own file timestamps.
public struct ManifestEnvelope: Codable, Equatable, Sendable {
    public var version: Int
    /// Base64 of the AES-256-GCM combined form (nonce + ciphertext + tag) over the
    /// canonical `Manifest` JSON.
    public var encryptedBody: String
    /// Hex HMAC-SHA-256 over this envelope with the field cleared.
    public var manifestHmac: String

    public init(version: Int = Manifest.currentVersion, encryptedBody: String, manifestHmac: String = "") {
        self.version = version
        self.encryptedBody = encryptedBody
        self.manifestHmac = manifestHmac
    }

    /// A copy with the HMAC cleared — the canonical bytes that are signed.
    public func bodyForSigning() -> ManifestEnvelope {
        var copy = self
        copy.manifestHmac = ""
        return copy
    }

    public func serialise() throws -> Data { try PlatformJSON.encode(self) }

    public static func parse(_ data: Data) throws -> ManifestEnvelope {
        try PlatformJSON.decode(ManifestEnvelope.self, from: data)
    }

    /// Peek at the version of whatever is in the folder without needing the key, so the
    /// caller can route a v1/v2 plaintext manifest to the legacy path and a v3 here.
    public static func peekVersion(_ data: Data) -> Int? {
        struct VersionOnly: Decodable { let version: Int }
        return (try? PlatformJSON.decode(VersionOnly.self, from: data))?.version
    }
}

public struct Manifest: Codable, Equatable, Sendable {
    /// v3 (2026-08-11) — the body is ENCRYPTED inside a `ManifestEnvelope`. v1/v2 were
    /// plain JSON.
    public static let currentVersion = 3
    /// Versions this client can process. A manifest with a HIGHER version than
    /// we understand is rejected rather than misread as v1.
    ///
    /// v1 and v2 stay READABLE so a folder written by an earlier build still syncs and is
    /// then rewritten as v3 on the next push — the upgrade is a push, not a migration step.
    /// Nothing is shipped, so this costs one decode branch and removes any chance of a
    /// tester's folder becoming unreadable.
    public static let supportedVersions = 1...3
    /// Tombstones older than this are pruned from the manifest on push.
    /// Raised 30 → 180 days (2026-07-01): a device offline past the retention
    /// window still holds its deleted Takes live, and push's self-heal step
    /// would re-upload them — resurrecting a month of deletions fleet-wide.
    /// Tombstones are ~90 bytes each, so six months of retention is near-free;
    /// the self-heal hold-back guard in `pushOutbound` covers devices absent
    /// even longer than this.
    public static let tombstoneRetention: TimeInterval = 180 * 24 * 3600

    public var version: Int
    public var updated: String         // ISO-8601
    public var schemaVersion: Int
    public var takes: [ManifestEntry]
    /// Deletion records (v2). Encoded only when non-empty so that v1 manifests
    /// (signed without the field) still verify after parsing.
    public var tombstones: [ManifestTombstone]
    /// Hex-encoded HMAC-SHA-256 of the canonical manifest body (this field empty).
    public var manifestHmac: String

    public init(
        version: Int = Manifest.currentVersion,
        updated: String,
        schemaVersion: Int = 1,
        takes: [ManifestEntry],
        tombstones: [ManifestTombstone] = [],
        manifestHmac: String = ""
    ) {
        self.version = version
        self.updated = updated
        self.schemaVersion = schemaVersion
        self.takes = takes
        self.tombstones = tombstones
        self.manifestHmac = manifestHmac
    }

    enum CodingKeys: String, CodingKey {
        case version, updated, schemaVersion, takes, tombstones, manifestHmac
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        updated = try c.decode(String.self, forKey: .updated)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        takes = try c.decode([ManifestEntry].self, forKey: .takes)
        tombstones = try c.decodeIfPresent([ManifestTombstone].self, forKey: .tombstones) ?? []
        manifestHmac = try c.decode(String.self, forKey: .manifestHmac)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(updated, forKey: .updated)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(takes, forKey: .takes)
        // Omit when empty: keeps the canonical signed bytes of a tombstone-free
        // manifest identical to the v1 format, so old signatures still verify.
        if !tombstones.isEmpty {
            try c.encode(tombstones, forKey: .tombstones)
        }
        try c.encode(manifestHmac, forKey: .manifestHmac)
    }

    /// A copy with the HMAC field cleared — the canonical body that is signed.
    public func bodyForSigning() -> Manifest {
        var copy = self
        copy.manifestHmac = ""
        return copy
    }

    public func serialise() throws -> Data { try PlatformJSON.encode(self) }

    public static func parse(_ data: Data) throws -> Manifest {
        try PlatformJSON.decode(Manifest.self, from: data)
    }

    // MARK: - v3 encrypted form (owner 2026-08-11)

    /// Seal this manifest into a v3 envelope. The envelope is returned UNSIGNED — the caller
    /// signs it through `ManifestSigner`, keeping signing in one place.
    public func sealed(with key: SymmetricKey) throws -> ManifestEnvelope {
        var body = self
        body.version = Manifest.currentVersion
        body.manifestHmac = ""   // the signature lives on the envelope, not the body
        let sealed = try CryptoService.encrypt(try body.serialise(), key: key)
        return ManifestEnvelope(encryptedBody: sealed.base64EncodedString())
    }

    /// Open a v3 envelope. Throws `SyncError.manifestSignatureInvalid` on a bad payload
    /// rather than a crypto error, so a corrupted manifest lands on the pull path's existing
    /// fail-closed branch instead of an unhandled failure mode.
    public static func opening(_ envelope: ManifestEnvelope, with key: SymmetricKey) throws -> Manifest {
        guard let ciphertext = Data(base64Encoded: envelope.encryptedBody) else {
            throw SyncError.manifestSignatureInvalid
        }
        do {
            var manifest = try Manifest.parse(try CryptoService.decrypt(ciphertext, key: key))
            // The envelope carries the authoritative version; the inner copy is incidental.
            manifest.version = envelope.version
            manifest.manifestHmac = envelope.manifestHmac
            return manifest
        } catch {
            throw SyncError.manifestSignatureInvalid
        }
    }

    public static let fileName = "catchlight-manifest.json"
}
