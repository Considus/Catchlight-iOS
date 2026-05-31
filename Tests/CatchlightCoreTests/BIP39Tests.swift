//
//  BIP39Tests.swift
//  CatchlightCoreTests
//
//  BIP-39 algorithm (Encryption Architecture §3, §5). Exercised with a synthetic
//  2048-word list — proves the entropy ⇄ checksum ⇄ index algorithm. Official
//  English-wordlist standard compliance is verified separately in the iOS target.
//

import XCTest
@testable import CatchlightCore

final class BIP39Tests: XCTestCase {
    private let bip39 = BIP39(wordlist: TestFixtures.syntheticWordlist())

    func testGeneratesTwelveWords() throws {
        let m = try bip39.generateMnemonic()
        XCTAssertEqual(m.count, 12)
    }

    func testGeneratedMnemonicValidatesAndRecoversEntropy() throws {
        let entropy = Data((0..<16).map { UInt8($0) })
        let m = try bip39.mnemonic(fromEntropy: entropy)
        XCTAssertEqual(m.count, 12)
        let recovered = try bip39.validate(mnemonic: m)
        XCTAssertEqual(recovered, entropy)
    }

    func testDeterministicForSameEntropy() throws {
        let entropy = Data(repeating: 0xAB, count: 16)
        XCTAssertEqual(try bip39.mnemonic(fromEntropy: entropy), try bip39.mnemonic(fromEntropy: entropy))
    }

    func testRandomMnemonicsValidate() throws {
        for _ in 0..<50 {
            let m = try bip39.generateMnemonic()
            XCTAssertNoThrow(try bip39.validate(mnemonic: m))
        }
    }

    func testInvalidChecksumRejected() throws {
        var m = try bip39.mnemonic(fromEntropy: Data(repeating: 0x01, count: 16))
        // Deterministic corruption: the last word's low 4 bits are the BIP-39
        // checksum, its high 7 bits are entropy. Flip one checksum bit while keeping
        // the entropy prefix identical → guaranteed checksum mismatch.
        let lastIdx = Int(m.last!.dropFirst())!
        let corruptedIdx = (lastIdx & ~0xF) | ((lastIdx & 0xF) ^ 0x1)
        m[m.count - 1] = "w\(corruptedIdx)"
        XCTAssertThrowsError(try bip39.validate(mnemonic: m)) { error in
            guard case CryptoError.invalidMnemonic = error else { return XCTFail("wrong error") }
        }
    }

    func testWordNotInListRejected() {
        let m = Array(repeating: "w0", count: 11) + ["not-a-real-word"]
        XCTAssertThrowsError(try bip39.validate(mnemonic: m))
    }

    func testWrongWordCountRejected() {
        XCTAssertThrowsError(try bip39.validate(mnemonic: ["w0", "w1", "w2"]))
    }

    func testWordlistMustBe2048Unique() {
        XCTAssertThrowsError(try BIP39Wordlist(words: ["a", "b"]))
        let dupes = Array(repeating: "x", count: 2048)
        XCTAssertThrowsError(try BIP39Wordlist(words: dupes))
    }
}
