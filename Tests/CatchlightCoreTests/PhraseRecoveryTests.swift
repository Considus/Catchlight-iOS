//
//  PhraseRecoveryTests.swift
//  CatchlightCoreTests — restore-from-phrase crypto core (Recovery & Migration v1.0, chunk 1)
//
//  Proves the validate-then-derive seam: a valid entered phrase yields the SAME master key
//  the generate path would store (so a second device decrypts the same data), tolerates
//  casing/whitespace, and rejects malformed input (count / unknown word / checksum).
//  Uses the synthetic 2048-word list (words "w0"…"w2047") — same fixture as BIP39Tests.
//

import XCTest
@testable import CatchlightCore

final class PhraseRecoveryTests: XCTestCase {

    private let bip39 = BIP39(wordlist: TestFixtures.syntheticWordlist())

    private func validMnemonic() throws -> [String] {
        try bip39.mnemonic(fromEntropy: Data(repeating: 0x2A, count: 16))
    }

    func testValidPhrase_derivesSameKeyAsGeneratePath() throws {
        let words = try validMnemonic()
        let recovered = try PhraseRecovery.recoverMasterKey(from: words, bip39: bip39)
        // Identical to what OnboardingViewModel.finishOnboarding stores for the same words.
        XCTAssertEqual(recovered, MasterKeyDerivation.deriveRaw(from: words))
        XCTAssertEqual(recovered.count, 32)
    }

    func testValidPhrase_toleratesCasingAndSurroundingWhitespace() throws {
        let words = try validMnemonic()
        let messy = words.enumerated().map { i, w in i == 0 ? "  \(w.uppercased())  " : w }
        XCTAssertEqual(try PhraseRecovery.recoverMasterKey(from: messy, bip39: bip39),
                       try PhraseRecovery.recoverMasterKey(from: words, bip39: bip39))
    }

    func testWrongWordCount_throws() throws {
        let eleven = Array(try validMnemonic().prefix(11))
        XCTAssertThrowsError(try PhraseRecovery.recoverMasterKey(from: eleven, bip39: bip39))
    }

    func testWordNotInList_throws() throws {
        var words = try validMnemonic()
        words[3] = "definitely-not-in-the-wordlist"
        XCTAssertThrowsError(try PhraseRecovery.recoverMasterKey(from: words, bip39: bip39))
    }

    func testChecksumMismatch_throws() throws {
        var words = try bip39.mnemonic(fromEntropy: Data(repeating: 0x01, count: 16))
        // Deterministic corruption (same technique as BIP39Tests): the last word's low 4 bits
        // are the checksum, high 7 bits are entropy — flip one checksum bit, keep the entropy.
        let lastIdx = Int(words.last!.dropFirst())!
        let corruptedIdx = (lastIdx & ~0xF) | ((lastIdx & 0xF) ^ 0x1)
        words[words.count - 1] = "w\(corruptedIdx)"
        XCTAssertThrowsError(try PhraseRecovery.recoverMasterKey(from: words, bip39: bip39))
    }

    func testBlankWordCollapsesToWrongCount_throws() throws {
        var words = try validMnemonic()
        words[5] = "   "   // a blank field → dropped → 11 words → rejected, not silently padded
        XCTAssertThrowsError(try PhraseRecovery.recoverMasterKey(from: words, bip39: bip39))
    }
}
