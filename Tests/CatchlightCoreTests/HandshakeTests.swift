//
//  HandshakeTests.swift
//  CatchlightCoreTests
//
//  Phase 5 brief §12.5 — second-device handshake (Encryption Architecture §6).
//

import XCTest
import CryptoKit
@testable import CatchlightCore

final class HandshakeTests: XCTestCase {

    // §12.5 — Ephemeral key pair generated; master key wrapped + unwrapped in a
    // simulated two-device flow.
    func testTwoDeviceWrapUnwrapRoundTrip() throws {
        let masterKey = SymmetricKey(size: .bits256)
        let masterKeyBytes = masterKey.withUnsafeBytes { Data($0) }

        // New device builds a request, holding its ephemeral private key in memory.
        let (request, newDevicePrivate) = DeviceHandshake.makeRequest(deviceIdentifier: "iPhone-15")

        // Original device approves and wraps the master key for the requester.
        let response = try DeviceHandshake.makeResponse(to: request, masterKey: masterKey)

        // New device unwraps using its retained ephemeral private key.
        let unwrapped = try DeviceHandshake.unwrapMasterKey(response: response, ephemeralPrivate: newDevicePrivate)
        XCTAssertEqual(unwrapped, masterKeyBytes)
    }

    // §12.5 — Expired handshake request (>15 minutes) is rejected.
    func testExpiredHandshakeRejected() throws {
        let masterKey = SymmetricKey(size: .bits256)
        let issued = Date()
        let (request, newDevicePrivate) = DeviceHandshake.makeRequest(deviceIdentifier: "iPad", now: issued)
        let response = try DeviceHandshake.makeResponse(to: request, masterKey: masterKey, now: issued)

        let sixteenMinutesLater = issued.addingTimeInterval(16 * 60)
        XCTAssertThrowsError(
            try DeviceHandshake.unwrapMasterKey(response: response, ephemeralPrivate: newDevicePrivate, now: sixteenMinutesLater)
        ) { error in
            XCTAssertEqual(error as? SyncError, .handshakeExpired)
        }
    }

    func testWithinExpiryAccepted() throws {
        let masterKey = SymmetricKey(size: .bits256)
        let issued = Date()
        let (request, priv) = DeviceHandshake.makeRequest(deviceIdentifier: "iPad", now: issued)
        let response = try DeviceHandshake.makeResponse(to: request, masterKey: masterKey, now: issued)
        let fourteenMin = issued.addingTimeInterval(14 * 60)
        XCTAssertNoThrow(try DeviceHandshake.unwrapMasterKey(response: response, ephemeralPrivate: priv, now: fourteenMin))
    }

    // The OTV alone is useless: an attacker with the cloud files but not the
    // requesting device's private key cannot unwrap (Encryption Architecture §6).
    func testWrongPrivateKeyCannotUnwrap() throws {
        let masterKey = SymmetricKey(size: .bits256)
        let (request, _) = DeviceHandshake.makeRequest(deviceIdentifier: "victim")
        let response = try DeviceHandshake.makeResponse(to: request, masterKey: masterKey)
        // Attacker uses a different ephemeral private key.
        let attackerPrivate = Curve25519.KeyAgreement.PrivateKey()
        XCTAssertThrowsError(
            try DeviceHandshake.unwrapMasterKey(response: response, ephemeralPrivate: attackerPrivate)
        ) { error in
            XCTAssertEqual(error as? CryptoError, .authenticationFailed)
        }
    }

    // §12.5 — Handshake files overwritten with random bytes before deletion.
    func testSecureDeleteOverwritesBeforeRemoval() throws {
        let folder = InMemoryCloudFolder()
        let name = "catchlight-device-request-\(UUID().uuidString).json"
        try folder.write(Data(repeating: 0x41, count: 256), to: name)
        try folder.secureDelete(name)
        XCTAssertNil(try folder.read(name), "file removed")
        XCTAssertEqual(folder.secureDeleteOverwroteBytes[name], 256, "overwritten with equal-length random bytes first")
    }
}
