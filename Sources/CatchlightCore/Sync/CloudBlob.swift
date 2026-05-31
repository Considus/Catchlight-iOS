//
//  CloudBlob.swift
//  CatchlightCore
//
//  The platform-agnostic JSON envelope for an encrypted Take in the cloud folder
//  (Phase 5 brief §5.6). This is the ONLY format written for Take blobs — no binary
//  property lists, no NSKeyedArchiver, no Core Data formats. A future web/Android
//  client reads this file, Base64-decodes `encryptedPayload`, and runs the same
//  ChaCha20-Poly1305 open with the per-item key derived from the same `uuid`.
//
//  Cloud filename: `{uuid}.clk` — UUID only, no metadata in the filename
//  (Encryption Architecture §10.5).
//
//      {
//        "version": 1,
//        "uuid": "550e8400-e29b-41d4-a716-446655440000",
//        "modified": "2026-05-28T07:00:00.000Z",
//        "encryptedPayload": "<Base64 nonce+ciphertext+tag>"
//      }
//

import Foundation

public struct CloudBlob: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let uuid: UUID
    /// ISO-8601 string. Explicit string field (not Date) for cross-platform clarity;
    /// mirrors `Take.modifiedAt`.
    public let modified: String
    /// Base64 of the ChaCha20-Poly1305 combined form (nonce + ciphertext + tag).
    public let encryptedPayload: String

    public init(version: Int = CloudBlob.currentVersion, uuid: UUID, modified: String, encryptedPayload: String) {
        self.version = version
        self.uuid = uuid
        self.modified = modified
        self.encryptedPayload = encryptedPayload
    }

    /// Build an envelope from a Take and its already-sealed ciphertext.
    public init(take: Take, sealed: Data) {
        self.version = CloudBlob.currentVersion
        self.uuid = take.id
        self.modified = ISO8601.string(from: take.modifiedAt)
        self.encryptedPayload = sealed.base64EncodedString()
    }

    /// The decoded ciphertext (nonce + ciphertext + tag), or nil if Base64 is bad.
    public var ciphertext: Data? {
        Data(base64Encoded: encryptedPayload)
    }

    /// The cloud-folder filename for this blob.
    public var fileName: String { "\(uuid.uuidString).clk" }

    public func serialise() throws -> Data { try PlatformJSON.encode(self) }

    public static func parse(_ data: Data) throws -> CloudBlob {
        try PlatformJSON.decode(CloudBlob.self, from: data)
    }
}
