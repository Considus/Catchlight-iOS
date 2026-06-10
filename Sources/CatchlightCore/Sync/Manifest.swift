//
//  Manifest.swift
//  CatchlightCore
//
//  The cloud-folder manifest (Encryption Architecture §11, Phase 5 brief §7.3).
//  `catchlight-manifest.json` is an HMAC-signed index of every synced Take. On
//  inbound sync the manifest signature is verified FIRST; then each downloaded
//  blob is verified against its per-entry HMAC before any decryption is attempted.
//
//      {
//        "version": 1,
//        "updated": "2026-05-28T07:00:00.000Z",
//        "schemaVersion": 1,
//        "takes": [
//          { "uuid": "...", "modified": "...", "hmac": "<hex HMAC of the .clk blob>" }
//        ],
//        "manifestHmac": "<hex HMAC of the manifest body>"
//      }
//
//  The `manifestHmac` field is computed over the manifest body with the field set
//  to empty, then filled in — so verification recomputes over the same canonical
//  body. Because PlatformJSON uses `.sortedKeys`, the body serialises deterministically.
//

import Foundation

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

public struct Manifest: Codable, Equatable, Sendable {
    public static let currentVersion = 2
    /// Versions this client can process. A manifest with a HIGHER version than
    /// we understand is rejected rather than misread as v1.
    public static let supportedVersions = 1...2
    /// Tombstones older than this are pruned from the manifest on push. 30 days
    /// is ample for every device of a single user to sync at least once.
    public static let tombstoneRetention: TimeInterval = 30 * 24 * 3600

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

    public static let fileName = "catchlight-manifest.json"
}
