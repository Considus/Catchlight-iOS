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
//  The bundled `bip39-english.txt` is the canonical 2048-word list from the BIP-39
//  reference, sourced from `trezor/python-mnemonic` (the upstream maintained by the
//  Bitcoin community). Its SHA-256 is pinned in `expectedSHA256` below; `load()`
//  recomputes the digest at runtime and refuses to proceed if it does not match —
//  a corrupted or substituted resource fails loudly rather than silently.
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

    /// Official BIP-39 english.txt SHA-256.
    /// Source: https://raw.githubusercontent.com/trezor/python-mnemonic/master/src/mnemonic/wordlist/english.txt
    public static let expectedSHA256 = "2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda"

    public static func load(bundle: Bundle = .main) throws -> BIP39Wordlist {
        guard let url = bundle.url(forResource: "bip39-english", withExtension: "txt") else {
            throw LoadError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256 else {
            throw LoadError.digestMismatch(expected: expectedSHA256, got: digest)
        }
        let words = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard words.count == 2048 else {
            throw LoadError.malformed("expected exactly 2048 words, got \(words.count)")
        }
        return try BIP39Wordlist(words: words)
    }
}
