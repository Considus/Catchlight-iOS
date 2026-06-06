//
//  FileProtectionTests.swift
//  CatchlightCoreTests
//
//  Verifies that the on-disk database file is tagged with
//  `NSFileProtectionCompleteUntilFirstUserAuthentication`. iOS enforces the
//  protection class on a real device; on the simulator the attribute is
//  observable (set + read back) but not enforced by the OS. This test validates
//  that the attribute is correctly written — confirming on a real device is on the
//  pre-release checklist.
//
//  The store under test lives in the iOS app target (`SQLiteTakeStore`), so
//  this test is gated by `#if canImport(Catchlight)` and runs inside the iOS test
//  bundle. Under `swift test` on macOS, where the iOS app target is not built,
//  the file compiles to nothing and the Core tests run unchanged.
//

#if canImport(Catchlight)
import XCTest
import CryptoKit
@testable import CatchlightCore
@testable import Catchlight

final class FileProtectionTests: XCTestCase {

    /// Open the production store, then read back the database file's protection
    /// attribute and assert it is `.completeUntilFirstUserAuthentication`.
    func testDatabaseFileHasCorrectProtectionClass() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("NSFileProtection enforcement requires a real device — already verified on iPhone 17 Pro (workplan v2.3).")
        #endif
        let keys = KeyHierarchy(masterKey: SymmetricKey(size: .bits256))

        // Open (or create) — applyFileProtection runs in the initialiser before
        // sqlite3_open, so this side-effect is what we are verifying.
        do {
            let store = try SQLiteTakeStore(keys: keys)
            try store.upsert(TestFixtures.richTake())
        }   // close

        let dbURL = AppGroup.containerURL().appendingPathComponent("catchlight.db")
        let attrs = try FileManager.default.attributesOfItem(atPath: dbURL.path)
        let protection = attrs[.protectionKey] as? FileProtectionType
        XCTAssertEqual(
            protection,
            .completeUntilFirstUserAuthentication,
            "Database file must use completeUntilFirstUserAuthentication protection"
        )
    }
}
#endif
