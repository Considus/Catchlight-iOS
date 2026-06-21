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
        // TEST SEAM (2026-06-10): redirect to a throwaway service so the suite
        // can NEVER touch (or delete!) the production privacy-phrase slot —
        // deleting the real phrase would be unrecoverable for a real user.
        // User presence is disabled: a .userPresence item cannot be read
        // headlessly and the simulator may have no enrolled biometrics.
        var config = MnemonicKeychain.Configuration()
        config.service = "com.considus.catchlight.tests"
        config.requireUserPresence = false
        MnemonicKeychain.configuration = config

        // Start every test from a clean (test-service) slot — a leftover phrase
        // from a previous run would mask an "exists() == false" expectation.
        MnemonicKeychain.delete()
    }

    override func tearDown() {
        MnemonicKeychain.delete()
        // Restore production defaults so no other suite inherits the test seam.
        MnemonicKeychain.configuration = MnemonicKeychain.Configuration()
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

    /// Repeated re-stores exercise the update-or-add path (owner 2026-06-21): each
    /// re-store after the first goes through `SecItemUpdate` (no delete window), the slot
    /// stays present throughout, and the final value is the last one written.
    func testMnemonicKeychain_repeatedStores_updateInPlace_noDataLoss() throws {
        try MnemonicKeychain.store(Self.phrase)
        try MnemonicKeychain.store(Self.alt)
        XCTAssertTrue(MnemonicKeychain.exists())
        try MnemonicKeychain.store(Self.phrase)
        XCTAssertTrue(MnemonicKeychain.exists())
        XCTAssertEqual(try XCTUnwrap(MnemonicKeychain.retrieve()), Self.phrase)
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
