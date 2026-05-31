//
//  Argon2id.swift
//  CatchlightCore
//
//  Argon2id is the ONLY cryptographic primitive in the whole system that Apple
//  CryptoKit does not provide. The Encryption Architecture (§3) and the Roadmap
//  (§4) both mandate the `libargon2` REFERENCE implementation specifically — not
//  a CryptoKit substitute, not PBKDF2 — because the master key must be re-derivable
//  byte-for-byte from the same mnemonic + salt on every future platform (iOS, the
//  WebCrypto/WASM web client, the Android/Tink client, the macOS client). Any
//  divergence in the KDF breaks cross-device and cross-platform recovery silently.
//
//  DESIGN: the portable core depends only on this protocol and on the fixed
//  parameter set. The concrete binding to the C library (`argon2id_hash_raw`) lives
//  in the iOS app target (`Catchlight/Security/LibArgon2.swift`) so that:
//    1. CatchlightCore stays pure-Swift and builds/tests on any platform; and
//    2. the master-key/recovery/PIN services are fully unit-testable by injecting
//       a deterministic double, with the real Argon2 swapped in for the app.
//
//  IMPORTANT (see Technical_Architecture_v1.0.md §6, and Encryption Architecture
//  §16 "libargon2 version audit confirmation"): byte-for-byte standard compliance
//  of the C binding MUST be verified against the official Argon2id known-answer
//  vectors (RFC 9106 / the reference repo's `kat-argon2id.log`) on a networked
//  build machine before release. This core treats Argon2 as an injected pure
//  function; it does not — and must not — re-implement it from memory.
//

import Foundation

/// The Argon2id cost parameters. Fixed to the OWASP-recommended minimums for
/// interactive logins (Encryption Architecture §3, Phase 5 brief §5.2). These are
/// non-negotiable and identical on every platform.
public struct Argon2Parameters: Equatable, Sendable {
    /// Memory cost in KiB. 131072 KiB = 128 MiB.
    public let memoryKiB: UInt32
    /// Time cost (iterations).
    public let iterations: UInt32
    /// Parallelism (lanes/threads).
    public let parallelism: UInt32
    /// Output length in bytes (256-bit master key).
    public let outputLength: Int

    public init(memoryKiB: UInt32, iterations: UInt32, parallelism: UInt32, outputLength: Int) {
        self.memoryKiB = memoryKiB
        self.iterations = iterations
        self.parallelism = parallelism
        self.outputLength = outputLength
    }

    /// The canonical Catchlight parameters: m = 128 MiB, t = 3, p = 4, 32-byte output.
    /// DO NOT ALTER (Phase 5 brief §5.2 "mandatory, do not alter").
    public static let catchlightMasterKey = Argon2Parameters(
        memoryKiB: 131072,   // 128 MiB
        iterations: 3,
        parallelism: 4,
        outputLength: 32
    )
}

/// Abstraction over an Argon2id implementation. The mnemonic and salt are passed as
/// raw bytes; the implementation must apply Argon2id (the hybrid `-id` variant) and
/// return exactly `parameters.outputLength` bytes.
public protocol Argon2idDeriving: Sendable {
    func deriveKey(passwordBytes: [UInt8], saltBytes: [UInt8], parameters: Argon2Parameters) throws -> Data
}

public extension Argon2idDeriving {
    /// Convenience: derive the 32-byte master key from a normalised mnemonic string
    /// and a salt, using the fixed Catchlight parameters.
    ///
    /// The mnemonic is encoded as UTF-8 of the NFKD-normalised, single-space-joined
    /// word list — the same byte sequence every platform must use as the Argon2
    /// "password" input so derivations match across clients.
    func deriveMasterKey(mnemonic: [String], salt: Data) throws -> Data {
        let normalised = mnemonic
            .map { $0.lowercased() }
            .joined(separator: " ")
        let pwBytes = Array(Data(normalised.decomposedStringWithCanonicalMapping.utf8))
        return try deriveKey(
            passwordBytes: pwBytes,
            saltBytes: Array(salt),
            parameters: .catchlightMasterKey
        )
    }
}
