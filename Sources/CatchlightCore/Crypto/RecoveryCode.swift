//
//  RecoveryCode.swift
//  CatchlightCore
//
//  A portable backup of a RAW master key, for accounts with no recoverable BIP-39 phrase
//  (legacy / pre-phrase installs, or ones that lost the phrase to the pre-2026-07-01
//  mnemonic-upsert bug) and for direct device-to-device transfer. The master key is 256-bit
//  and was NOT derived from a stored phrase, so it can't be re-expressed as the normal 12-word
//  mnemonic — derivation is one-way. Instead we serialise the raw key into a versioned,
//  checksummed code the user saves (as a QR image or a copyable string) and enters on a new
//  device, which imports it straight into its keychain.
//
//  SECURITY: the encoded key is the root secret in the clear — it decrypts everything. It must
//  be treated EXACTLY like the privacy phrase: Face-ID-gated to reveal, and the user warned to
//  store it as securely as a password. The checksum guards against transcription/scan
//  corruption, NOT against tampering (it isn't a MAC — anyone with the code has the key).
//

import Foundation
import CryptoKit

public enum RecoveryCode {

    /// Human-visible scheme tag — "Catchlight Key, version 1". Also lets a restore screen
    /// tell a recovery code from a 12-word phrase at a glance.
    public static let scheme = "CLK1"
    private static let version: UInt8 = 1
    private static let keyLength = 32
    private static let checksumLength = 4

    public enum DecodeError: Error, Equatable {
        case malformed, badScheme, badVersion, checksumMismatch, wrongKeyLength
    }

    /// Encode a 32-byte master key as a recovery code string: `CLK1-<base64url(version‖key‖checksum)>`.
    public static func encode(masterKey: Data) -> String {
        precondition(masterKey.count == keyLength, "master key must be \(keyLength) bytes")
        var signed = Data([version])
        signed.append(masterKey)
        let checksum = Data(SHA256.hash(data: signed)).prefix(checksumLength)
        return scheme + "-" + base64url(signed + checksum)
    }

    /// Decode + verify a recovery code back to the 32-byte master key, or throw.
    public static func decode(_ code: String) throws -> Data {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dash = trimmed.firstIndex(of: "-") else { throw DecodeError.malformed }
        guard trimmed[trimmed.startIndex..<dash] == scheme else { throw DecodeError.badScheme }
        let body = String(trimmed[trimmed.index(after: dash)...])
        guard let payload = base64urlDecode(body) else { throw DecodeError.malformed }
        let bytes = [UInt8](payload)
        guard bytes.count == 1 + keyLength + checksumLength else { throw DecodeError.wrongKeyLength }
        guard bytes[0] == version else { throw DecodeError.badVersion }
        let signed = Data(bytes[0 ..< (1 + keyLength)])
        let checksum = Data(bytes[(1 + keyLength)...])
        guard Data(SHA256.hash(data: signed)).prefix(checksumLength) == checksum else {
            throw DecodeError.checksumMismatch
        }
        return Data(bytes[1 ..< (1 + keyLength)])
    }

    // MARK: - base64url

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64urlDecode(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}
