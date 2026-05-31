//
//  CryptoTests.swift
//  CatchlightCoreTests
//
//  Phase 5 brief §12.1 — encryption layer (highest priority).
//

import XCTest
import CryptoKit
@testable import CatchlightCore

final class CryptoTests: XCTestCase {

    private func masterKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    // §12.1 — Argon2id produces deterministic output for the same mnemonic + salt.
    // (Verified here against the injected KDF contract; real Argon2 byte-compliance
    //  is covered by the official KAT in the iOS target — see TestSupport notes.)
    func testKDFDeterministicForSameInput() throws {
        let kdf = InsecureMockArgon2idKDF()
        let mnemonic = ["abandon", "ability", "able", "about", "above", "absent",
                        "absorb", "abstract", "absurd", "abuse", "access", "accident"]
        let salt = Data(repeating: 0x10, count: 16)
        let k1 = try kdf.deriveMasterKey(mnemonic: mnemonic, salt: salt)
        let k2 = try kdf.deriveMasterKey(mnemonic: mnemonic, salt: salt)
        XCTAssertEqual(k1, k2)
        XCTAssertEqual(k1.count, 32)
    }

    func testKDFDifferentSaltDifferentOutput() throws {
        let kdf = InsecureMockArgon2idKDF()
        let mnemonic = ["zone", "zoo", "zero", "zebra", "youth", "yellow",
                        "year", "wrong", "world", "word", "wood", "wolf"]
        let a = try kdf.deriveMasterKey(mnemonic: mnemonic, salt: Data(repeating: 1, count: 16))
        let b = try kdf.deriveMasterKey(mnemonic: mnemonic, salt: Data(repeating: 2, count: 16))
        XCTAssertNotEqual(a, b)
    }

    func testCatchlightArgon2ParametersAreOWASPMinimums() {
        // §5.2 — mandatory, do not alter.
        let p = Argon2Parameters.catchlightMasterKey
        XCTAssertEqual(p.memoryKiB, 131072)   // 128 MiB
        XCTAssertEqual(p.iterations, 3)
        XCTAssertEqual(p.parallelism, 4)
        XCTAssertEqual(p.outputLength, 32)
    }

    // §12.1 — HKDF produces deterministic output for the same master key + info.
    func testHKDFDeterministic() {
        let mk = masterKey()
        let h = KeyHierarchy(masterKey: mk)
        XCTAssertEqual(
            h.databaseKey().withUnsafeBytes { Data($0) },
            KeyHierarchy(masterKey: mk).databaseKey().withUnsafeBytes { Data($0) }
        )
    }

    // §12.1 — Two different Take UUIDs produce two different per-item keys.
    func testDifferentUUIDsDifferentItemKeys() {
        let h = KeyHierarchy(masterKey: masterKey())
        let k1 = h.itemKey(takeUUID: UUID()).withUnsafeBytes { Data($0) }
        let k2 = h.itemKey(takeUUID: UUID()).withUnsafeBytes { Data($0) }
        XCTAssertNotEqual(k1, k2)
    }

    // §12.1 — Distinct info strings (db vs hmac) yield distinct keys (key separation).
    func testKeySeparationAcrossPurposes() {
        let h = KeyHierarchy(masterKey: masterKey())
        let db = h.databaseKey().withUnsafeBytes { Data($0) }
        let hmac = h.manifestHMACKey().withUnsafeBytes { Data($0) }
        XCTAssertNotEqual(db, hmac)
    }

    // §12.1 — encryptTake + decryptTake round-trip produces identical plaintext.
    func testEncryptDecryptRoundTrip() throws {
        let mk = masterKey()
        let uuid = UUID()
        let plaintext = Data("the small light that makes everything feel alive".utf8)
        let combined = try encryptTake(plaintext, masterKey: mk, takeUUID: uuid)
        let recovered = try decryptTake(combined, masterKey: mk, takeUUID: uuid)
        XCTAssertEqual(recovered, plaintext)
    }

    // §12.1 — Different encryptTake calls for same Take produce different ciphertext.
    func testFreshNoncePerEncryption() throws {
        let mk = masterKey()
        let uuid = UUID()
        let pt = Data("same plaintext".utf8)
        let c1 = try encryptTake(pt, masterKey: mk, takeUUID: uuid)
        let c2 = try encryptTake(pt, masterKey: mk, takeUUID: uuid)
        XCTAssertNotEqual(c1, c2, "random 12-byte nonce per seal → different ciphertext")
        // Both still decrypt to the same plaintext.
        XCTAssertEqual(try decryptTake(c1, masterKey: mk, takeUUID: uuid), pt)
        XCTAssertEqual(try decryptTake(c2, masterKey: mk, takeUUID: uuid), pt)
    }

    // §12.1 — Decryption of tampered ciphertext throws an authentication error.
    func testTamperedCiphertextFailsAEAD() throws {
        let mk = masterKey()
        let uuid = UUID()
        var combined = try encryptTake(Data("secret".utf8), masterKey: mk, takeUUID: uuid)
        combined[combined.count - 1] ^= 0xFF   // flip a tag byte
        XCTAssertThrowsError(try decryptTake(combined, masterKey: mk, takeUUID: uuid)) { error in
            XCTAssertEqual(error as? CryptoError, .authenticationFailed)
        }
    }

    // §12.1 — Wrong per-item key (wrong UUID) fails to decrypt.
    func testWrongUUIDFailsToDecrypt() throws {
        let mk = masterKey()
        let combined = try encryptTake(Data("x".utf8), masterKey: mk, takeUUID: UUID())
        XCTAssertThrowsError(try decryptTake(combined, masterKey: mk, takeUUID: UUID()))
    }

    func testMalformedCiphertextThrows() {
        let mk = masterKey()
        XCTAssertThrowsError(try decryptTake(Data([0x00, 0x01]), masterKey: mk, takeUUID: UUID()))
    }

    // Whole-Take payload round-trip through TakeCrypto.
    func testTakeCryptoRoundTrip() throws {
        let keys = KeyHierarchy(masterKey: masterKey())
        let crypto = TakeCrypto(keys: keys)
        let take = TestFixtures.richTake()
        let sealed = try crypto.seal(take)
        let recovered = try crypto.open(sealed, takeUUID: take.id)
        XCTAssertEqual(recovered, take)
    }
}
