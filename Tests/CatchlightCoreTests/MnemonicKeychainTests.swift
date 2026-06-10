//
//  MnemonicKeychainTests.swift
//  CatchlightCoreTests — Task 7.1
//
//  Exercises the real iOS Keychain via `MnemonicKeychain` (added in Task 3.12)
//  so the Settings → Privacy phrase reveal path is provably stable across:
//  store / overwrite / retrieve / delete. Gated to the iOS app target — under
//  `swift test` on macOS the Catchlight module isn't available and the suite
//  is skipped automatically.
//
//  No mocking: this hits the device Keychain under the same access group as
//  the production app, so a regression in the Keychain query attributes
//  surfaces here as well.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

final class MnemonicKeychainTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Start every test from a clean slot — a leftover phrase from a previous
        // run would mask an "exists() == false" expectation.
        MnemonicKeychain.delete()
    }

    override func tearDown() {
        MnemonicKeychain.delete()
        super.tearDown()
    }

    private static let phrase = [
        "abandon","abandon","abandon","abandon","abandon","abandon",
        "abandon","abandon","abandon","abandon","abandon","about"
    ]
    private static let alt = [
        "legal","winner","thank","year","wave","sausage",
        "worth","useful","legal","winner","thank","yellow"
    ]

    func testMnemonicKeychain_storeThenRetrieveRoundTrip() throws {
        try MnemonicKeychain.store(Self.phrase)
        let read = try XCTUnwrap(MnemonicKeychain.retrieve())
        XCTAssertEqual(read, Self.phrase)
    }

    func testMnemonicKeychain_existsReflectsStorage() throws {
        XCTAssertFalse(MnemonicKeychain.exists())
        try MnemonicKeychain.store(Self.phrase)
        XCTAssertTrue(MnemonicKeychain.exists())
    }

    /// Storing a second phrase MUST overwrite the first — the Keychain layer
    /// must not accumulate duplicates that a later retrieve would pick from at
    /// random.
    func testMnemonicKeychain_secondStoreOverwritesFirst() throws {
        try MnemonicKeychain.store(Self.phrase)
        try MnemonicKeychain.store(Self.alt)
        let read = try XCTUnwrap(MnemonicKeychain.retrieve())
        XCTAssertEqual(read, Self.alt)
    }

    func testMnemonicKeychain_deleteRemovesPhrase() throws {
        try MnemonicKeychain.store(Self.phrase)
        MnemonicKeychain.delete()
        XCTAssertNil(MnemonicKeychain.retrieve())
        XCTAssertFalse(MnemonicKeychain.exists())
    }

    /// `retrieve()` returns nil when nothing was ever stored — the Settings
    /// reveal flow relies on this to decide between the explainer screen and
    /// the PIN gate.
    func testMnemonicKeychain_retrieveBeforeAnyStoreReturnsNil() {
        XCTAssertNil(MnemonicKeychain.retrieve())
    }
}
#endif
