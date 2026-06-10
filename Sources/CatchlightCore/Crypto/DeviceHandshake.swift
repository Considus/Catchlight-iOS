//
//  DeviceHandshake.swift
//  CatchlightCore
//
//  Hardened second-device setup (Encryption Architecture §6, Phase 5 brief §7.7).
//
//  An ephemeral X25519 key pair binds the wrapped master key to the requesting
//  device, so the one-time value (OTV) left in the cloud folder is cryptographically
//  useless to anyone reading the folder (including its version history): deriving
//  the wrapping key also requires the ECDH shared secret, which requires a private
//  key that never leaves device memory.
//
//      wrappingKey = HKDF( IKM: ECDH(ephPriv, peerPub) XOR OTV,
//                          info: "catchlight-device-handshake-v1" )
//      wrappedMasterKey = ChaCha20-Poly1305.seal(masterKey, using: wrappingKey)
//
//  This type implements the cryptographic core (key generation, wrap, unwrap,
//  expiry checking). The cloud-folder file writing/polling and the secure-delete
//  overwrite (steps 3–4, 9, 13) live in the iOS target's sync layer.
//

import Foundation
import CryptoKit

/// Written by the NEW device to `catchlight-device-request-{uuid}.json`.
public struct HandshakeRequest: Codable, Equatable, Sendable {
    public let requestId: UUID
    public let ephemeralPublicKey: String   // Base64 X25519 raw public key (32 bytes)
    public let deviceIdentifier: String
    public let timestamp: String            // ISO-8601

    public init(requestId: UUID, ephemeralPublicKey: String, deviceIdentifier: String, timestamp: String) {
        self.requestId = requestId
        self.ephemeralPublicKey = ephemeralPublicKey
        self.deviceIdentifier = deviceIdentifier
        self.timestamp = timestamp
    }

    public var fileName: String { "catchlight-device-request-\(requestId.uuidString).json" }
}

/// Written by the ORIGINAL device after the user approves. Models both response
/// files from §6 step 9 (wrapped key blob + OTV plaintext) plus the original
/// device's ephemeral public key the new device needs to re-derive the shared
/// secret, and the expiry the new device must check (§6 step 10).
public struct HandshakeResponse: Codable, Equatable, Sendable {
    public let requestId: UUID
    public let originalDevicePublicKey: String  // Base64 X25519 raw public key
    public let wrappedMasterKey: String         // Base64 ChaCha20-Poly1305 combined
    public let oneTimeValue: String             // Base64 32-byte OTV (plaintext; useless alone)
    public let expiry: String                   // ISO-8601, 15 minutes after issue

    public init(requestId: UUID, originalDevicePublicKey: String, wrappedMasterKey: String, oneTimeValue: String, expiry: String) {
        self.requestId = requestId
        self.originalDevicePublicKey = originalDevicePublicKey
        self.wrappedMasterKey = wrappedMasterKey
        self.oneTimeValue = oneTimeValue
        self.expiry = expiry
    }
}

public enum DeviceHandshake {

    public static let expiryInterval: TimeInterval = 15 * 60   // 15 minutes (§6 step 9)

    /// Short authentication string (2026-06-10 hardening).
    ///
    /// THREAT: the user's approval is the only gate on a handshake request. An
    /// attacker with WRITE access to the cloud folder during an open handshake
    /// window can overwrite the request file with their own public key and a
    /// plausible device name; the user — who genuinely is adding a device —
    /// approves, and the master key is wrapped to the attacker's key.
    ///
    /// MITIGATION: both devices derive a 6-digit code from the request's public
    /// key + id. The NEW device displays it; the ORIGINAL device shows it inside
    /// the existing approval prompt ("Approve device — code 481 263"). If the
    /// request file was substituted, the codes differ and the user declines. This
    /// is the cryptographic minimum: nothing else binds the approved request to
    /// the user's actual new device. UI surfaces MUST display this code in any
    /// future multi-device flow (no flow ships in v1.0).
    public static func confirmationCode(for request: HandshakeRequest) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("catchlight-handshake-sas-v1".utf8))
        hasher.update(data: Data(request.requestId.uuidString.uppercased().utf8))
        hasher.update(data: Data(request.ephemeralPublicKey.utf8))
        let digest = Data(hasher.finalize())
        // First 4 bytes → big-endian UInt32 → 6 decimal digits (zero-padded).
        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%06d", value % 1_000_000)
    }

    /// Derive the wrapping key shared by both devices.
    /// - Parameters:
    ///   - ephemeralPrivate: this device's ephemeral X25519 private key.
    ///   - peerPublic: the other device's ephemeral X25519 public key.
    ///   - oneTimeValue: the 32-byte OTV (must be exactly 32 bytes).
    static func wrappingKey(
        ephemeralPrivate: Curve25519.KeyAgreement.PrivateKey,
        peerPublic: Curve25519.KeyAgreement.PublicKey,
        oneTimeValue: Data
    ) throws -> SymmetricKey {
        guard oneTimeValue.count == 32 else { throw CryptoError.malformedCiphertext }
        let shared = try ephemeralPrivate.sharedSecretFromKeyAgreement(with: peerPublic)
        // IKM = shared_secret XOR OTV  (Encryption Architecture §6 step 7)
        var sharedBytes = shared.withUnsafeBytes { Data($0) }   // 32 bytes
        var ikm = Data(count: 32)
        defer {
            // Zero both intermediate secret buffers.
            ikm.resetBytes(in: 0..<ikm.count)
            sharedBytes.resetBytes(in: 0..<sharedBytes.count)
        }
        for i in 0..<32 { ikm[i] = sharedBytes[i] ^ oneTimeValue[i] }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            info: Data(KeyInfo.deviceHandshake.utf8),
            outputByteCount: 32
        )
    }

    /// ORIGINAL device: generate OTV + ephemeral key pair and wrap the master key
    /// for the requesting device. Returns the response to publish, the master key
    /// stays on-device.
    public static func makeResponse(
        to request: HandshakeRequest,
        masterKey: SymmetricKey,
        now: Date = Date()
    ) throws -> HandshakeResponse {
        guard let peerPubData = Data(base64Encoded: request.ephemeralPublicKey) else {
            throw CryptoError.malformedCiphertext
        }
        let peerPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPubData)

        let ephemeralPrivate = Curve25519.KeyAgreement.PrivateKey()
        let otv = SecureRandom.bytes(32)   // hard-fails on CSPRNG error

        let wrappingKey = try wrappingKey(
            ephemeralPrivate: ephemeralPrivate,
            peerPublic: peerPublic,
            oneTimeValue: otv
        )
        var masterKeyData = masterKey.withUnsafeBytes { Data($0) }
        defer { masterKeyData.resetBytes(in: 0..<masterKeyData.count) }
        let sealed = try ChaChaPoly.seal(masterKeyData, using: wrappingKey)

        let expiry = ISO8601.string(from: now.addingTimeInterval(expiryInterval))
        return HandshakeResponse(
            requestId: request.requestId,
            originalDevicePublicKey: ephemeralPrivate.publicKey.rawRepresentation.base64EncodedString(),
            wrappedMasterKey: sealed.combined.base64EncodedString(),
            oneTimeValue: otv.base64EncodedString(),
            expiry: expiry
        )
    }

    /// NEW device: unwrap the master key using this device's ephemeral private key.
    /// Validates expiry first (§6 step 10).
    /// - Returns: the 32-byte master key bytes.
    public static func unwrapMasterKey(
        response: HandshakeResponse,
        ephemeralPrivate: Curve25519.KeyAgreement.PrivateKey,
        now: Date = Date()
    ) throws -> Data {
        guard let expiryDate = ISO8601.date(from: response.expiry), now <= expiryDate else {
            throw SyncError.handshakeExpired
        }
        guard
            let peerPubData = Data(base64Encoded: response.originalDevicePublicKey),
            let otv = Data(base64Encoded: response.oneTimeValue),
            let wrapped = Data(base64Encoded: response.wrappedMasterKey)
        else { throw CryptoError.malformedCiphertext }

        let peerPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPubData)
        let wrappingKey = try wrappingKey(
            ephemeralPrivate: ephemeralPrivate,
            peerPublic: peerPublic,
            oneTimeValue: otv
        )
        do {
            let box = try ChaChaPoly.SealedBox(combined: wrapped)
            return try ChaChaPoly.open(box, using: wrappingKey)
        } catch {
            throw CryptoError.authenticationFailed
        }
    }

    /// Build the request payload for the new device, returning the request to
    /// publish and the ephemeral private key to hold in memory only.
    public static func makeRequest(
        deviceIdentifier: String,
        now: Date = Date()
    ) -> (request: HandshakeRequest, ephemeralPrivate: Curve25519.KeyAgreement.PrivateKey) {
        let priv = Curve25519.KeyAgreement.PrivateKey()
        let req = HandshakeRequest(
            requestId: UUID(),
            ephemeralPublicKey: priv.publicKey.rawRepresentation.base64EncodedString(),
            deviceIdentifier: deviceIdentifier,
            timestamp: ISO8601.string(from: now)
        )
        return (req, priv)
    }
}

private extension Data {
    /// Overwrite bytes in place with zeros. Uses `memset_s` (guaranteed not to be
    /// optimised away) on the actual backing buffer — the previous
    /// `replaceSubrange` implementation could trigger a copy-on-write
    /// reallocation, zeroing a fresh copy while the original key bytes lived on.
    mutating func resetBytes(in range: Range<Int>) {
        withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            memset_s(base + range.lowerBound, raw.count - range.lowerBound, 0, range.count)
        }
    }
}
