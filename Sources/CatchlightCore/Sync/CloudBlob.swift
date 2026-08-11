//
//  CloudBlob.swift
//  CatchlightCore
//
//  The platform-agnostic JSON envelope for an encrypted Take in the cloud folder
//  (Phase 5 brief §5.6). This is the ONLY format written for Take blobs — no binary
//  property lists, no NSKeyedArchiver, no Core Data formats. A future web/Android
//  client reads this file, Base64-decodes `encryptedPayload`, and runs the same
//  AES-256-GCM open with the per-item key derived from the same `uuid`.
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
    /// v2 (owner 2026-08-11, D-196) — `uuid` and `modified` are no longer WRITTEN.
    ///
    /// Both were plaintext metadata that nothing ever read back: the pull path takes the
    /// uuid from the manifest entry (and the filename), and takes the modification time
    /// from the DECRYPTED Take's `modifiedAt`. Verified by inspection across the whole sync
    /// engine before removal — `blob.uuid` and `blob.modified` had no readers at all. So
    /// every `.clk` file was publishing a per-Take edit timestamp for nothing.
    public static let currentVersion = 2
    /// Versions this client can process. A blob with a HIGHER version than we
    /// understand is quarantined rather than misread as v1 (2026-07-01) —
    /// mirrors `Manifest.supportedVersions`, which had this guard from the
    /// start while the per-Take envelope had none.
    ///
    /// v1 stays readable so a folder written by an earlier build still syncs; the next push
    /// rewrites each blob as v2, so the upgrade needs no migration step.
    public static let supportedVersions = 1...2

    public let version: Int
    /// The Take's id. Present on a v1 blob, absent from v2 — hence Optional. It is NOT
    /// needed to read a blob (the caller already knows which uuid it fetched), only to
    /// name one on the way out.
    public let uuid: UUID?
    /// ISO-8601 string. v1 only; never written in v2. Kept solely so a v1 blob round-trips
    /// rather than losing a field on decode.
    public let modified: String?
    /// Base64 of the AES-256-GCM combined form (nonce + ciphertext + tag).
    public let encryptedPayload: String

    public init(version: Int = CloudBlob.currentVersion,
                uuid: UUID? = nil,
                modified: String? = nil,
                encryptedPayload: String) {
        self.version = version
        self.uuid = uuid
        self.modified = modified
        self.encryptedPayload = encryptedPayload
    }

    /// Build an envelope from a Take and its already-sealed ciphertext. The uuid is retained
    /// in memory for `fileName` but is NOT encoded (see `encode(to:)`).
    public init(take: Take, sealed: Data) {
        self.version = CloudBlob.currentVersion
        self.uuid = take.id
        self.modified = nil
        self.encryptedPayload = sealed.base64EncodedString()
    }

    /// The decoded ciphertext (nonce + ciphertext + tag), or nil if Base64 is bad.
    public var ciphertext: Data? {
        Data(base64Encoded: encryptedPayload)
    }

    /// The cloud-folder filename for this blob. Only meaningful on the WRITE path, where the
    /// uuid is always known; a blob decoded from v2 has none, and callers there already hold
    /// the uuid they fetched by.
    public var fileName: String? {
        uuid.map { "\($0.uuidString).clk" }
    }

    /// The cloud-folder filename for a given Take id — the form the sync engine uses, since
    /// it always knows the id independently of the envelope.
    public static func fileName(for uuid: UUID) -> String { "\(uuid.uuidString).clk" }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case version, uuid, modified, encryptedPayload
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        // decodeIfPresent both ways: a v2 blob simply has neither.
        uuid = try c.decodeIfPresent(UUID.self, forKey: .uuid)
        modified = try c.decodeIfPresent(String.self, forKey: .modified)
        encryptedPayload = try c.decode(String.self, forKey: .encryptedPayload)
    }

    /// Writes the v2 shape ONLY — version + ciphertext. The uuid and modified time are
    /// deliberately never emitted, whatever this value happens to hold in memory: that is
    /// the whole point of the version bump, so it must not depend on the caller remembering
    /// to nil them out.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(encryptedPayload, forKey: .encryptedPayload)
    }

    public func serialise() throws -> Data { try PlatformJSON.encode(self) }

    public static func parse(_ data: Data) throws -> CloudBlob {
        try PlatformJSON.decode(CloudBlob.self, from: data)
    }
}
