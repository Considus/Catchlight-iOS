//
//  EnglishWordlistTests.swift
//  CatchlightCoreTests
//
//  Verifies the bundled official BIP-39 English wordlist:
//    • 2048 lines
//    • SHA-256 matches the pinned digest in `EnglishWordlist.expectedSHA256`
//    • canonical anchor words ("abandon" first, "zoo" last) are present
//    • mnemonics generated against it only use words from the bundled list
//
//  The loader (`EnglishWordlist.load()`) lives in the iOS app target — it depends
//  on `Bundle.main` and is unreachable under `swift test`. The file is gated by
//  `#if canImport(Catchlight)` so the macOS Core test run is unaffected and the
//  iOS test bundle (XcodeGen `CatchlightTests`) executes it.
//

#if canImport(Catchlight)
import XCTest
import CryptoKit
@testable import CatchlightCore
@testable import Catchlight

final class EnglishWordlistTests: XCTestCase {

    func testBundledWordlistMatchesPinnedSHA256() throws {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: "bip39-english", withExtension: "txt") else {
            XCTFail("bip39-english.txt missing from app bundle"); return
        }
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, EnglishWordlist.expectedSHA256)
    }

    func testWordlistLoadsAs2048Words() throws {
        let wl = try EnglishWordlist.load(bundle: Bundle(for: Self.self))
        XCTAssertEqual(wl.words.count, 2048)
    }

    func testKnownAnchorWordsPresent() throws {
        let wl = try EnglishWordlist.load(bundle: Bundle(for: Self.self))
        XCTAssertEqual(wl.words.first, "abandon")
        XCTAssertEqual(wl.words.last, "zoo")
    }

    func testGeneratedMnemonicOnlyUsesOfficialWords() throws {
        let wl = try EnglishWordlist.load(bundle: Bundle(for: Self.self))
        let allowed = Set(wl.words)
        let bip = BIP39(wordlist: wl)
        for _ in 0..<25 {
            let m = try bip.generateMnemonic()
            XCTAssertEqual(m.count, 12)
            for word in m {
                XCTAssertTrue(allowed.contains(word), "mnemonic contains non-official word \(word)")
            }
        }
    }
}
#endif
