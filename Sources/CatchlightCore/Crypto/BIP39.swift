//
//  BIP39.swift
//  CatchlightCore
//
//  BIP-39 mnemonic generation and validation (Encryption Architecture §3, §5;
//  Phase 5 brief §5.1). 12 words = 128 bits of entropy + 4 checksum bits = 132
//  bits = 12 × 11-bit indices.
//
//  This file implements the BIP-39 ALGORITHM (entropy ⇄ checksum ⇄ word indices),
//  which is fully verifiable and tested here. The 2048-word English wordlist is a
//  standard DATA ARTIFACT and is INJECTED via `BIP39Wordlist`, not hard-coded from
//  memory: reproducing 2048 words from memory risks a silent single-word error
//  that would break BIP-39 checksum validity and cross-platform interoperability.
//  The production app loads the official wordlist as a bundled resource verified by
//  its SHA-256 digest (see Catchlight/Security/BIP39Wordlist+English.swift in the
//  iOS target). Tests use a deterministic synthetic 2048-word list to prove the
//  algorithm without claiming standard-wordlist compliance.
//

import Foundation
import CryptoKit

/// A validated BIP-39 wordlist: exactly 2048 unique words.
public struct BIP39Wordlist: Sendable {
    public let words: [String]
    private let index: [String: Int]

    public enum WordlistError: Error, Equatable, Sendable {
        case wrongCount(Int)
        case notUnique
    }

    public init(words: [String]) throws {
        guard words.count == 2048 else { throw WordlistError.wrongCount(words.count) }
        let lowered = words.map { $0.lowercased() }
        let set = Set(lowered)
        guard set.count == 2048 else { throw WordlistError.notUnique }
        self.words = lowered
        var idx = [String: Int]()
        for (i, w) in lowered.enumerated() { idx[w] = i }
        self.index = idx
    }

    func index(of word: String) -> Int? { index[word.lowercased()] }
}

public struct BIP39: Sendable {
    public let wordlist: BIP39Wordlist

    public init(wordlist: BIP39Wordlist) {
        self.wordlist = wordlist
    }

    /// Generate a fresh 12-word mnemonic from 128 bits of secure entropy
    /// (`SecRandomCopyBytes` via SecureRandom).
    public func generateMnemonic() throws -> [String] {
        let entropy = SecureRandom.bytes(16)   // 128 bits
        return try mnemonic(fromEntropy: entropy)
    }

    /// Deterministically derive a mnemonic from given 128-bit entropy.
    public func mnemonic(fromEntropy entropy: Data) throws -> [String] {
        guard entropy.count == 16 else { throw CryptoError.invalidMnemonic("entropy must be 16 bytes") }
        let checksumBits = entropy.count * 8 / 32          // 4 bits for 128-bit entropy
        let hash = SHA256.hash(data: entropy)
        let hashByte0 = hash.withUnsafeBytes { $0[0] }

        var bits: [Bool] = []
        bits.reserveCapacity(132)
        for byte in entropy { for i in (0..<8).reversed() { bits.append((byte >> i) & 1 == 1) } }
        for i in 0..<checksumBits { bits.append((hashByte0 >> (7 - i)) & 1 == 1) }

        // 132 bits → 12 groups of 11.
        var result: [String] = []
        for group in 0..<(bits.count / 11) {
            var value = 0
            for bit in 0..<11 { value = (value << 1) | (bits[group * 11 + bit] ? 1 : 0) }
            result.append(wordlist.words[value])
        }
        return result
    }

    /// Validate a mnemonic: every word must be in the wordlist and the BIP-39
    /// checksum must match. Returns the recovered entropy on success.
    @discardableResult
    public func validate(mnemonic: [String]) throws -> Data {
        guard mnemonic.count == 12 else {
            throw CryptoError.invalidMnemonic("expected 12 words, got \(mnemonic.count)")
        }
        var bits: [Bool] = []
        bits.reserveCapacity(132)
        for word in mnemonic {
            guard let idx = wordlist.index(of: word) else {
                throw CryptoError.invalidMnemonic("word not in wordlist: \(word)")
            }
            for bit in (0..<11).reversed() { bits.append((idx >> bit) & 1 == 1) }
        }
        let entropyBits = 128
        let checksumBits = 4
        precondition(bits.count == entropyBits + checksumBits)

        // Reassemble entropy bytes.
        var entropy = Data(count: 16)
        for byteIdx in 0..<16 {
            var b: UInt8 = 0
            for bit in 0..<8 { b = (b << 1) | (bits[byteIdx * 8 + bit] ? 1 : 0) }
            entropy[byteIdx] = b
        }
        // Recompute and compare checksum.
        let hash = SHA256.hash(data: entropy)
        let hashByte0 = hash.withUnsafeBytes { $0[0] }
        for i in 0..<checksumBits {
            let expected = (hashByte0 >> (7 - i)) & 1 == 1
            if bits[entropyBits + i] != expected {
                throw CryptoError.invalidMnemonic("checksum mismatch")
            }
        }
        return entropy
    }
}
