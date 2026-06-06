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

    // §12.1 — HKDF master-key derivation is deterministic for the same mnemonic.
    // The mnemonic is the entropy source; the salt and info bytes are fixed domain
    // strings (no random per-account salt). This is the cross-platform recovery
    // contract: same mnemonic → same 32-byte master key on every Catchlight client.
    func testMasterKeyDeterministicForSameMnemonic() {
        let mnemonic = ["abandon", "ability", "able", "about", "above", "absent",
                        "absorb", "abstract", "absurd", "abuse", "access", "accident"]
        let k1 = MasterKeyDerivation.deriveRaw(from: mnemonic)
        let k2 = MasterKeyDerivation.deriveRaw(from: mnemonic)
        XCTAssertEqual(k1, k2)
        XCTAssertEqual(k1.count, 32)
    }

    // §12.1 — Different mnemonics produce different master keys.
    func testMasterKeyDifferentMnemonicsDifferentKeys() {
        let m1 = ["abandon", "ability", "able", "about", "above", "absent",
                  "absorb", "abstract", "absurd", "abuse", "access", "accident"]
        let m2 = ["zone", "zoo", "zero", "zebra", "youth", "yellow",
                  "year", "wrong", "world", "word", "wood", "wolf"]
        let a = MasterKeyDerivation.deriveRaw(from: m1)
        let b = MasterKeyDerivation.deriveRaw(from: m2)
        XCTAssertNotEqual(a, b)
    }

    // §12.1 — Mnemonic word casing is normalised: the same words in different
    // case must produce the same master key.
    func testMasterKeyNormalisesCase() {
        let lower = ["abandon", "ability", "able", "about", "above", "absent",
                     "absorb", "abstract", "absurd", "abuse", "access", "accident"]
        let upper = lower.map { $0.uppercased() }
        XCTAssertEqual(
            MasterKeyDerivation.deriveRaw(from: lower),
            MasterKeyDerivation.deriveRaw(from: upper)
        )
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

    // §12.1 — encryptTake + decryptTake round-trip produces identical plaintext
    // (AES-256-GCM via CryptoKit).
    func testEncryptDecryptRoundTrip() throws {
        let mk = masterKey()
        let uuid = UUID()
        let plaintext = Data("the small light that makes everything feel alive".utf8)
        let combined = try encryptTake(plaintext, masterKey: mk, takeUUID: uuid)
        let recovered = try decryptTake(combined, masterKey: mk, takeUUID: uuid)
        XCTAssertEqual(recovered, plaintext)
    }

    // §12.1 — `CryptoService.encrypt` / `decrypt` round-trip (the generic AEAD).
    func testCryptoServiceRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let pt = Data("hello, gcm".utf8)
        let combined = try CryptoService.encrypt(pt, key: key)
        XCTAssertEqual(try CryptoService.decrypt(combined, key: key), pt)
    }

    // §12.1 — Different encryptTake calls for same Take produce different
    // ciphertext (CryptoKit generates a fresh random 12-byte nonce per seal).
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

    // §12.1 — Wrong AES-GCM key (different SymmetricKey) fails closed.
    func testWrongKeyFailsToDecrypt() throws {
        let keyA = SymmetricKey(size: .bits256)
        let keyB = SymmetricKey(size: .bits256)
        let combined = try CryptoService.encrypt(Data("secret".utf8), key: keyA)
        XCTAssertThrowsError(try CryptoService.decrypt(combined, key: keyB)) { error in
            XCTAssertEqual(error as? CryptoError, .authenticationFailed)
        }
    }

    // §12.1 — Per-item key for Take A differs from per-item key for Take B
    // even under the same master key (UUID-bound HKDF info).
    func testPerItemKeyIsUUIDBound() {
        let mk = masterKey()
        let a = itemKey(masterKey: mk, takeUUID: UUID()).withUnsafeBytes { Data($0) }
        let b = itemKey(masterKey: mk, takeUUID: UUID()).withUnsafeBytes { Data($0) }
        XCTAssertNotEqual(a, b)
    }

    // §12.1 — Per-item key is deterministic for the same master key + UUID.
    func testPerItemKeyDeterministic() {
        let mk = masterKey()
        let uuid = UUID()
        let a = itemKey(masterKey: mk, takeUUID: uuid).withUnsafeBytes { Data($0) }
        let b = itemKey(masterKey: mk, takeUUID: uuid).withUnsafeBytes { Data($0) }
        XCTAssertEqual(a, b)
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
