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

public struct Manifest: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var updated: String         // ISO-8601
    public var schemaVersion: Int
    public var takes: [ManifestEntry]
    /// Hex-encoded HMAC-SHA-256 of the canonical manifest body (this field empty).
    public var manifestHmac: String

    public init(
        version: Int = Manifest.currentVersion,
        updated: String,
        schemaVersion: Int = 1,
        takes: [ManifestEntry],
        manifestHmac: String = ""
    ) {
        self.version = version
        self.updated = updated
        self.schemaVersion = schemaVersion
        self.takes = takes
        self.manifestHmac = manifestHmac
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
