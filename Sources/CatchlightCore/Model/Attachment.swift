//
//  Attachment.swift
//  CatchlightCore
//
//  A binary attachment on a Take (Phase 5 brief §4.6).
//
//  v1.0 STATUS: the `attachments` array on Take is always empty in v1.0; this
//  struct exists for v1.1 document scanning and image attachment (Roadmap §3,
//  Horizon 1). Each attachment carries its OWN ciphertext + HMAC so large binary
//  blobs can be synced and integrity-checked independently of the Take payload.
//

import Foundation

public struct Attachment: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID

    /// e.g. "image/jpeg", "application/pdf".
    public var mimeType: String

    /// Encrypted binary blob (AES-256-GCM combined form). Already ciphertext.
    public var encryptedData: Data

    /// HMAC-SHA-256 of `encryptedData`, for integrity verification before decrypt.
    public var hmac: Data

    /// Encrypted OCR text added to the search index (v1.1). `nil` in v1.0.
    public var ocrText: String?

    public init(
        id: UUID = UUID(),
        mimeType: String,
        encryptedData: Data,
        hmac: Data,
        ocrText: String? = nil
    ) {
        self.id = id
        self.mimeType = mimeType
        self.encryptedData = encryptedData
        self.hmac = hmac
        self.ocrText = ocrText
    }
}
