//
//  BIP39Wordlist+English.swift
//  Catchlight (iOS app target)
//
//  Loads the official BIP-39 English wordlist (2048 words) from a bundled resource
//  and verifies it by SHA-256 before use. The wordlist is a STANDARD DATA ARTIFACT,
//  not something to hand-type into source: a single wrong/transposed word would
//  silently produce non-standard mnemonics that fail to round-trip on other BIP-39
//  implementations (Web/Android), breaking cross-platform recovery.
//
//  SETUP (one-time, on a networked machine):
//    1. Download the canonical list:
//       https://github.com/bitcoin/bips/blob/master/bip-0039/english.txt
//    2. Add it to the app target as `bip39-english.txt` (one word per line, 2048
//       lines, lowercase, NFKD).
//    3. Confirm its digest and paste it into `expectedSHA256` below. The official
//       file's SHA-256 is widely published; verify against a trusted source.
//
//  At runtime, `load()` recomputes the digest and refuses to proceed if it does not
//  match — so a corrupted or substituted resource fails loudly rather than silently.
//

import Foundation
import CryptoKit
import CatchlightCore

public enum EnglishWordlist {

    public enum LoadError: Error {
        case resourceMissing
        case digestMismatch(expected: String, got: String)
        case malformed(String)
    }

    /// Official BIP-39 english.txt SHA-256. MUST be filled in during setup (above).
    /// Left empty so an unverified build fails the check rather than trusting an
    /// unconfirmed value baked in from memory.
    public static let expectedSHA256 = ""   // TODO(setup): paste the verified digest

    public static func load(bundle: Bundle = .main) throws -> BIP39Wordlist {
        guard let url = bundle.url(forResource: "bip39-english", withExtension: "txt") else {
            throw LoadError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard !expectedSHA256.isEmpty else {
            throw LoadError.malformed("expectedSHA256 not configured — see setup notes")
        }
        guard digest == expectedSHA256 else {
            throw LoadError.digestMismatch(expected: expectedSHA256, got: digest)
        }
        let words = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return try BIP39Wordlist(words: words)
    }
}
