//
//  ManifestSigner.swift
//  CatchlightCore
//
//  HMAC-SHA-256 signing and verification for the cloud folder (Encryption
//  Architecture §11, Phase 5 brief §7.3). The HMAC key is derived from the master
//  key via HKDF with `info: "catchlight-manifest-hmac-v1"` (KeyHierarchy).
//
//  Two integrity surfaces:
//    1. Per-blob: HMAC over the raw `.clk` blob bytes → goes in each manifest entry.
//    2. Manifest body: HMAC over the canonical manifest body (with the hmac field
//       cleared) → goes in `manifestHmac`.
//
//  Verification uses CryptoKit's `isValidAuthenticationCode`, which is constant-time.
//

import Foundation
import CryptoKit

public struct ManifestSigner: Sendable {
    private let hmacKey: SymmetricKey

    public init(keys: KeyHierarchy) {
        self.hmacKey = keys.manifestHMACKey()
    }

    public init(hmacKey: SymmetricKey) {
        self.hmacKey = hmacKey
    }

    // MARK: - Per-blob HMAC

    /// Hex-encoded HMAC-SHA-256 of an encrypted `.clk` blob's bytes.
    public func blobHMACHex(_ blobBytes: Data) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: blobBytes, using: hmacKey)
        return Self.hex(Data(code))
    }

    /// Constant-time verification of a blob against its expected hex HMAC.
    public func verifyBlob(_ blobBytes: Data, expectedHex: String) -> Bool {
        guard let expected = Self.bytes(fromHex: expectedHex) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(expected, authenticating: blobBytes, using: hmacKey)
    }

    // MARK: - Manifest body HMAC

    /// Returns a copy of the manifest with `manifestHmac` filled in.
    public func sign(_ manifest: Manifest) throws -> Manifest {
        let body = try manifest.bodyForSigning().serialise()
        let code = HMAC<SHA256>.authenticationCode(for: body, using: hmacKey)
        var signed = manifest
        signed.manifestHmac = Self.hex(Data(code))
        return signed
    }

    /// Constant-time verification of a manifest's own signature.
    public func verify(_ manifest: Manifest) throws -> Bool {
        guard let expected = Self.bytes(fromHex: manifest.manifestHmac) else { return false }
        let body = try manifest.bodyForSigning().serialise()
        return HMAC<SHA256>.isValidAuthenticationCode(expected, authenticating: body, using: hmacKey)
    }

    // MARK: - v3 envelope signing (owner 2026-08-11)

    /// Sign the ENCRYPTED envelope (manifest v3). AES-GCM's tag already authenticates the
    /// sealed body, so this is belt-and-braces — but it keeps `SyncEngine`'s "verify the
    /// signature first, quarantine everything on failure" flow identical to v1/v2, rather
    /// than replacing a well-understood failure path with a new one at the same time as
    /// changing the format.
    public func sign(_ envelope: ManifestEnvelope) throws -> ManifestEnvelope {
        let body = try envelope.bodyForSigning().serialise()
        let code = HMAC<SHA256>.authenticationCode(for: body, using: hmacKey)
        var signed = envelope
        signed.manifestHmac = Self.hex(Data(code))
        return signed
    }

    public func verify(_ envelope: ManifestEnvelope) throws -> Bool {
        guard let expected = Self.bytes(fromHex: envelope.manifestHmac) else { return false }
        let body = try envelope.bodyForSigning().serialise()
        return HMAC<SHA256>.isValidAuthenticationCode(expected, authenticating: body, using: hmacKey)
    }

    // MARK: - Hex helpers

    static func hex<D: DataProtocol>(_ data: D) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func bytes(fromHex hex: String) -> Data? {
        guard hex.count % 2 == 0 else { return nil }
        var out = Data(capacity: hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            out.append(b)
            idx = next
        }
        return out
    }
}
