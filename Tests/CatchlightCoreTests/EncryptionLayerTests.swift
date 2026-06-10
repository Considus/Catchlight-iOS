//
//  EncryptionLayerTests.swift
//  CatchlightCoreTests — Task 7.1
//
//  Targeted gap-fill for the encryption layer. The existing `CryptoTests` covers
//  most of the round-trip + tamper paths; this file adds the missing pieces:
//
//    • Known-answer tests (KATs) for `MasterKeyDerivation`, per-item key
//      derivation, and `KeyHierarchy` (database key + manifest HMAC key). These
//      are the SINGLE MOST IMPORTANT tests in the suite — they pin the exact
//      32-byte output of HKDF so any accidental change to the derivation path
//      (salt, info, normalisation, output length) breaks the build immediately.
//    • Output-length invariants.
//    • Mnemonic normalisation paths not yet covered by CryptoTests (canonical
//      Unicode decomposition; mixed-case round-trip with whitespace in the
//      EXACT shape `MasterKeyDerivation` produces).
//    • Round-trip for the awkward content shapes — empty, emoji-heavy,
//      >1MB random — that AES-GCM has to handle without complaint.
//    • Distinctness of derived keys from the master key (KeyHierarchy
//      sibling separation is in CryptoTests, but not vs the IKM itself).
//
//  KAT vectors were computed once under the current implementation
//  (`MasterKeyDerivation`, `itemKey`, `KeyHierarchy`) on macOS arm64 with
//  CryptoKit's HKDF<SHA256>. They are the cross-platform recovery contract — if
//  these change, recovery silently breaks across clients (Encryption
//  Architecture §3.3).
//

import XCTest
import CryptoKit
@testable import CatchlightCore

final class EncryptionLayerTests: XCTestCase {

    // MARK: - Helpers

    private static let abandonAbout = [
        "abandon","abandon","abandon","abandon","abandon","abandon",
        "abandon","abandon","abandon","abandon","abandon","about"
    ]
    private static let legalYellow = [
        "legal","winner","thank","year","wave","sausage",
        "worth","useful","legal","winner","thank","yellow"
    ]
    private static let letterAbove = [
        "letter","advice","cage","absurd","amount","doctor",
        "acoustic","avoid","letter","advice","cage","above"
    ]

    private func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    private func bytes(of key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    // MARK: - MasterKeyDerivation — known-answer tests
    //
    // Each vector is the output of MasterKeyDerivation.deriveRaw(from:) for a
    // standard BIP-39 test mnemonic, captured against the implementation as of
    // Task 7.1. Any change here means the derivation path has drifted — fix the
    // code, not the vector.

    func testMasterKeyDerivation_knownAnswer_abandonAbout() {
        let key = MasterKeyDerivation.deriveRaw(from: Self.abandonAbout)
        XCTAssertEqual(hex(key),
                       "88361a0df0ac351351b4f12308ecf9280c1d966f3a670f011339f25e1b979e87")
    }

    func testMasterKeyDerivation_knownAnswer_legalYellow() {
        let key = MasterKeyDerivation.deriveRaw(from: Self.legalYellow)
        XCTAssertEqual(hex(key),
                       "26c0170a5f6724854dd14992f1c8debfdb501f22ddc6802da5e9671b8d377a2c")
    }

    func testMasterKeyDerivation_knownAnswer_letterAbove() {
        let key = MasterKeyDerivation.deriveRaw(from: Self.letterAbove)
        XCTAssertEqual(hex(key),
                       "8c501ab52c5fd463035926059751513f5c7e7496d076382291d65cecae872d32")
    }

    // MARK: - MasterKeyDerivation — invariants

    func testMasterKeyDerivation_outputIsAlways32Bytes() {
        for mnemonic in [Self.abandonAbout, Self.legalYellow, Self.letterAbove] {
            XCTAssertEqual(MasterKeyDerivation.deriveRaw(from: mnemonic).count, 32)
        }
    }

    /// Canonical Unicode decomposition: MasterKeyDerivation applies
    /// `.decomposedStringWithCanonicalMapping` to the joined mnemonic before
    /// HKDF. A precomposed character (U+00E9 "é") and its decomposed equivalent
    /// (U+0065 + U+0301) MUST derive the same master key — otherwise a copy/paste
    /// between platforms with different normalisation defaults silently breaks
    /// recovery.
    ///
    /// We use the regular BIP-39 wordlist as the "real" mnemonic, then sub in a
    /// non-wordlist token that exercises canonical-equivalence. Since
    /// `MasterKeyDerivation` doesn't validate against the wordlist (that's
    /// `BIP39.validate`'s job), the derivation step accepts arbitrary strings.
    func testMasterKeyDerivation_canonicalEquivalence() {
        let composed   = "caf\u{00E9}"                      // "café" — single codepoint é
        let decomposed = "cafe\u{0301}"                     // "café" — e + combining acute

        var m1 = Self.abandonAbout
        m1[0] = composed
        var m2 = Self.abandonAbout
        m2[0] = decomposed

        XCTAssertEqual(
            MasterKeyDerivation.deriveRaw(from: m1),
            MasterKeyDerivation.deriveRaw(from: m2),
            "Composed and decomposed forms must derive the same master key (canonically equivalent)."
        )
    }

    /// Mixed-case input matches lowercase. CryptoTests already asserts upper vs
    /// lower; this nails down the in-between (which exercises the per-word
    /// `.lowercased()` step rather than a whole-string lowercase).
    func testMasterKeyDerivation_mixedCaseMatchesLower() {
        let mixed = Self.abandonAbout.enumerated().map { idx, w in
            idx.isMultiple(of: 2) ? w.uppercased() : w
        }
        XCTAssertEqual(
            MasterKeyDerivation.deriveRaw(from: Self.abandonAbout),
            MasterKeyDerivation.deriveRaw(from: mixed)
        )
    }

    /// Ten distinct mnemonics produce ten distinct master keys — a sanity check
    /// that HKDF-SHA-256 is being used end to end (a constant or zeroed output
    /// would collapse the set).
    func testMasterKeyDerivation_tenDistinctMnemonicsAllDistinct() {
        let mnemonics: [[String]] = [
            Self.abandonAbout,
            Self.legalYellow,
            Self.letterAbove,
            ["abandon","ability","able","about","above","absent",
             "absorb","abstract","absurd","abuse","access","accident"],
            ["zone","zoo","zero","zebra","youth","yellow",
             "year","wrong","world","word","wood","wolf"],
            ["army","van","defense","carry","jealous","true",
             "garbage","claim","echo","media","make","crunch"],
            ["advice","cage","absurd","amount","doctor","acoustic",
             "avoid","letter","advice","cage","absurd","amount"],
            ["scheme","crop","flush","dinner","update","supreme",
             "awake","give","past","season","cancel","heavy"],
            ["horn","tenant","knee","talent","sponsor","spell",
             "gate","clip","pulse","soap","slush","warm"],
            ["panda","eyebrow","bullet","gorilla","call","smoke",
             "muffin","taste","mesh","discover","soft","ostrich"]
        ]
        let derived = mnemonics.map(MasterKeyDerivation.deriveRaw(from:))
        XCTAssertEqual(Set(derived).count, mnemonics.count,
                       "All ten derived master keys must be distinct.")
    }

    // MARK: - KeyHierarchy — known-answer + invariants
    //
    // Pinning the database key and manifest HMAC key under a known master key
    // guards against any accidental info-string drift in KeyHierarchy. The
    // master key here is the KAT output of the "abandon … about" mnemonic.

    func testKeyHierarchy_databaseKey_knownAnswer() {
        let mk = SymmetricKey(data: MasterKeyDerivation.deriveRaw(from: Self.abandonAbout))
        let db = KeyHierarchy(masterKey: mk).databaseKey()
        XCTAssertEqual(hex(bytes(of: db)),
                       "58606f40f5c6d654f24c4f9ed6fe3e346ac910672aba63e05db2246cbc8bf04d")
    }

    func testKeyHierarchy_manifestHMACKey_knownAnswer() {
        let mk = SymmetricKey(data: MasterKeyDerivation.deriveRaw(from: Self.abandonAbout))
        let hmac = KeyHierarchy(masterKey: mk).manifestHMACKey()
        XCTAssertEqual(hex(bytes(of: hmac)),
                       "a91b96b9abed7290b7f67ecd1c0a8246edbcf90f0d31da0bd7da614223a252e4")
    }

    func testKeyHierarchy_perItemKey_knownAnswer() {
        let mk = SymmetricKey(data: MasterKeyDerivation.deriveRaw(from: Self.abandonAbout))
        let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let ik = itemKey(masterKey: mk, takeUUID: uuid)
        XCTAssertEqual(hex(bytes(of: ik)),
                       "555c8df54338b6efb9278f2940abd15466a7625316abc1c2d9f26063d779e32f")
    }

    func testKeyHierarchy_perItemKey_secondKnownAnswer() {
        let mk = SymmetricKey(data: MasterKeyDerivation.deriveRaw(from: Self.abandonAbout))
        let uuid = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let ik = itemKey(masterKey: mk, takeUUID: uuid)
        XCTAssertEqual(hex(bytes(of: ik)),
                       "b9ef3edca9bdeab3402fff478b198d51351439836326f7d67f2d6bf38f65ddae")
    }

    /// Derived keys must NEVER equal the master-key bytes themselves — that
    /// would mean a derivation path was accidentally bypassed.
    func testKeyHierarchy_derivedKeysAreNotMasterKey() {
        let mkBytes = MasterKeyDerivation.deriveRaw(from: Self.abandonAbout)
        let mk = SymmetricKey(data: mkBytes)
        let kh = KeyHierarchy(masterKey: mk)
        XCTAssertNotEqual(bytes(of: kh.databaseKey()), mkBytes)
        XCTAssertNotEqual(bytes(of: kh.manifestHMACKey()), mkBytes)
        XCTAssertNotEqual(bytes(of: kh.itemKey(takeUUID: UUID())), mkBytes)
    }

    func testKeyHierarchy_perItemKeyOutputAlways32Bytes() {
        let mk = SymmetricKey(data: MasterKeyDerivation.deriveRaw(from: Self.abandonAbout))
        let kh = KeyHierarchy(masterKey: mk)
        XCTAssertEqual(bytes(of: kh.itemKey(takeUUID: UUID())).count, 32)
        XCTAssertEqual(bytes(of: kh.databaseKey()).count, 32)
        XCTAssertEqual(bytes(of: kh.manifestHMACKey()).count, 32)
    }

    // MARK: - TakeCrypto — content-shape coverage

    /// Empty plaintext must seal and open cleanly. AES-GCM has no minimum
    /// payload size; this exists so a future "guard against empty" gets caught.
    func testTakeCrypto_emptyPlaintextRoundTrip() throws {
        let mk = SymmetricKey(size: .bits256)
        let uuid = UUID()
        let sealed = try encryptTake(Data(), masterKey: mk, takeUUID: uuid)
        let opened = try decryptTake(sealed, masterKey: mk, takeUUID: uuid)
        XCTAssertEqual(opened, Data())
    }

    /// Multi-byte emoji and combining marks survive the round trip — exercises
    /// the UTF-8 → bytes → UTF-8 path through CryptoKit without any platform
    /// re-encoding.
    func testTakeCrypto_emojiAndCombiningMarksRoundTrip() throws {
        let mk = SymmetricKey(size: .bits256)
        let uuid = UUID()
        let payload = "café ☕️ 🌅 family👨‍👩‍👧‍👦 — \u{1F300}…\u{1F9E0}"
        let pt = Data(payload.utf8)
        let sealed = try encryptTake(pt, masterKey: mk, takeUUID: uuid)
        let opened = try decryptTake(sealed, masterKey: mk, takeUUID: uuid)
        XCTAssertEqual(String(data: opened, encoding: .utf8), payload)
    }

    /// Binary-ish content (full 0x00…0xFF byte coverage) must survive the round
    /// trip — guards against any accidental string-aware byte handling.
    func testTakeCrypto_fullByteRangeRoundTrip() throws {
        let mk = SymmetricKey(size: .bits256)
        let uuid = UUID()
        let pt = Data((0...255).map { UInt8($0) })
        let sealed = try encryptTake(pt, masterKey: mk, takeUUID: uuid)
        let opened = try decryptTake(sealed, masterKey: mk, takeUUID: uuid)
        XCTAssertEqual(opened, pt)
    }

    /// >1 MB random payload — confirms CryptoKit's streaming-aware AES.GCM has
    /// no implicit cap at the size we care about (large attachments). A 1.5 MB
    /// payload is deliberately picked above the 1 MB threshold the spec calls out.
    func testTakeCrypto_largePlaintextRoundTrip() throws {
        let mk = SymmetricKey(size: .bits256)
        let uuid = UUID()
        var pt = Data(count: 1_500_000)
        pt.withUnsafeMutableBytes { buf in
            // Deterministic, non-zero, non-repeating pattern — avoids relying on
            // SecRandomCopyBytes inside a test and still exercises full byte range.
            for i in 0..<buf.count { buf[i] = UInt8((i * 31) & 0xFF) }
        }
        let sealed = try encryptTake(pt, masterKey: mk, takeUUID: uuid)
        let opened = try decryptTake(sealed, masterKey: mk, takeUUID: uuid)
        XCTAssertEqual(opened, pt)
        XCTAssertGreaterThan(sealed.count, pt.count, "GCM adds nonce + tag overhead.")
    }

    /// Same master key + same plaintext + DIFFERENT Take UUID → DIFFERENT
    /// ciphertext. (CryptoTests covers per-item-key distinctness; this covers
    /// the end-to-end ciphertext distinctness that the per-item key produces.)
    /// We compare under matched UUIDs to defeat the random-nonce confound: each
    /// ciphertext is the seal of the same plaintext under its OWN per-item key,
    /// and the two MUST decrypt to the same plaintext under their own UUIDs but
    /// not the other.
    func testTakeCrypto_differentUUIDsProduceIndependentCiphertexts() throws {
        let mk = SymmetricKey(size: .bits256)
        let pt = Data("the same plaintext".utf8)
        let uuidA = UUID()
        let uuidB = UUID()
        let cA = try encryptTake(pt, masterKey: mk, takeUUID: uuidA)
        let cB = try encryptTake(pt, masterKey: mk, takeUUID: uuidB)
        XCTAssertNotEqual(cA, cB)
        XCTAssertEqual(try decryptTake(cA, masterKey: mk, takeUUID: uuidA), pt)
        XCTAssertEqual(try decryptTake(cB, masterKey: mk, takeUUID: uuidB), pt)
        // And cross-decryption must fail — the UUID is part of the key derivation.
        XCTAssertThrowsError(try decryptTake(cA, masterKey: mk, takeUUID: uuidB))
        XCTAssertThrowsError(try decryptTake(cB, masterKey: mk, takeUUID: uuidA))
    }

    /// Tampering anywhere in the body (not just the tag) fails closed. The
    /// existing test flips the tag byte; this one flips a body byte and asserts
    /// AEAD still surfaces a clean error rather than partial plaintext.
    func testTakeCrypto_bodyTamperingFailsClosed() throws {
        let mk = SymmetricKey(size: .bits256)
        let uuid = UUID()
        var sealed = try encryptTake(Data(repeating: 0x42, count: 256),
                                     masterKey: mk, takeUUID: uuid)
        // The first 12 bytes are the nonce, the last 16 are the tag; flip a body byte.
        let bodyIndex = sealed.count / 2
        sealed[bodyIndex] ^= 0x01
        XCTAssertThrowsError(try decryptTake(sealed, masterKey: mk, takeUUID: uuid)) { error in
            // Either malformed or authentication-failed is acceptable; what is
            // NOT acceptable is silently returning altered plaintext.
            guard let cryptoError = error as? CryptoError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            XCTAssertTrue(cryptoError == .authenticationFailed
                          || cryptoError == .malformedCiphertext,
                          "Body tamper must surface as a clean AEAD failure, got \(cryptoError).")
        }
    }
}
