//
//  CaptureInboxWiringTests.swift
//  CatchlightAppTests — R7: the app's side of the sealed capture queue.
//
//  Core seals and opens (Catchlight-Core CaptureInboxTests). What only the app can get wrong
//  is the wiring: an unlock must publish the key writers seal to, and a reset must withdraw it.
//  These run against the real App Group defaults, the ones the share extension writes.
//

import XCTest
import CryptoKit
import CatchlightCore
@testable import Catchlight

final class CaptureInboxWiringTests: XCTestCase {

    override func tearDown() {
        let defaults = UserDefaults(suiteName: CaptureRouting.appGroupSuite)
        // A fresh key opens nothing, so every sealed entry these tests queued reads as unopenable.
        let anyKey = KeyHierarchy(masterKey: SymmetricKey(size: .bits256)).captureInboxPrivateKey()
        CaptureRouting.clearShared(CaptureRouting.unopenableSharedEntries(opening: anyKey, defaults: defaults),
                                   defaults: defaults)
        CaptureRouting.clearInboxKey(defaults: defaults)
        super.tearDown()
    }

    @MainActor
    func testUnlock_publishesTheInboxKey_soAShareSealsToThisAccount() {
        CaptureRouting.clearInboxKey()
        XCTAssertFalse(CaptureRouting.enqueueShared("before any unlock"), "no key, so the share is refused")

        let keys = KeyHierarchy(masterKey: SymmetricKey(size: .bits256))
        SessionController().adopt(keys)

        XCTAssertTrue(CaptureRouting.enqueueShared("shared while the app was closed"))
        let inbox = keys.captureInboxPrivateKey()
        XCTAssertEqual(CaptureRouting.sharedQueue(opening: inbox).map(\.text), ["shared while the app was closed"])
        XCTAssertTrue(CaptureRouting.unopenableSharedEntries(opening: inbox).isEmpty)
    }

    @MainActor
    func testAnotherAccountsUnlock_leavesEarlierCapturesUnopenable() {
        let before = KeyHierarchy(masterKey: SymmetricKey(size: .bits256))
        SessionController().adopt(before)
        CaptureRouting.enqueueShared("made for the old account")

        let after = KeyHierarchy(masterKey: SymmetricKey(size: .bits256))
        SessionController().adopt(after)

        let inbox = after.captureInboxPrivateKey()
        XCTAssertEqual(CaptureRouting.sharedQueue(opening: inbox), [])
        XCTAssertEqual(CaptureRouting.unopenableSharedEntries(opening: inbox).count, 1)
    }
}
