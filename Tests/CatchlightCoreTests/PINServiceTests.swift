//
//  PINServiceTests.swift
//  CatchlightCoreTests — Task 3.12
//
//  Covers PINPolicy (relaxed to 6-digit numeric for Task 3.12) and the set →
//  verify → reset round trip via the iOS Keychain.
//
//  PINService lives in the iOS app target and writes to the device Keychain, so
//  these tests are gated by `#if canImport(Catchlight)` — they run inside the
//  iOS test bundle. Under `swift test` on macOS the Core tests run unchanged.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

final class PINServiceTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        // Always leave the device Keychain clean — PIN survives test runs
        // otherwise and trips the "already set" assertions on a later run.
        PINService().reset()
    }

    // MARK: - PINPolicy

    func test_policy_accepts_6_digit_numeric() {
        XCTAssertNil(PINPolicy.rejectionReason(for: "123456"))
        XCTAssertNil(PINPolicy.rejectionReason(for: "987654"))
    }

    func test_policy_accepts_6_plus_alphanumeric() {
        XCTAssertNil(PINPolicy.rejectionReason(for: "letme1"))
        XCTAssertNil(PINPolicy.rejectionReason(for: "abc123def"))
    }

    func test_policy_rejects_short_numeric() {
        XCTAssertNotNil(PINPolicy.rejectionReason(for: "1234"))
        XCTAssertNotNil(PINPolicy.rejectionReason(for: "12345"))
    }

    func test_policy_rejects_short_alphanumeric() {
        XCTAssertNotNil(PINPolicy.rejectionReason(for: "ab1"))
        XCTAssertNotNil(PINPolicy.rejectionReason(for: "ab12"))
    }

    // MARK: - set / verify round trip

    func test_setPIN_then_verify_correct_returns_true() throws {
        let svc = PINService()
        try svc.setPIN("136912")
        XCTAssertTrue(try svc.verify("136912"))
        XCTAssertEqual(svc.failedAttempts, 0)
    }

    func test_setPIN_then_verify_wrong_returns_false_and_increments() throws {
        let svc = PINService()
        try svc.setPIN("136912")
        XCTAssertFalse(try svc.verify("000000"))
        XCTAssertEqual(svc.failedAttempts, 1)
    }

    func test_setPIN_replaces_previous_PIN() throws {
        let svc = PINService()
        try svc.setPIN("136912")
        try svc.setPIN("246810")
        XCTAssertFalse(try svc.verify("136912"))
        XCTAssertTrue(try svc.verify("246810"))
    }

    func test_reset_clears_PIN() throws {
        let svc = PINService()
        try svc.setPIN("136912")
        svc.reset()
        XCTAssertThrowsError(try svc.verify("136912")) { error in
            // notFound is what we expect once the salt slot is gone.
            guard case KeychainError.notFound = error else {
                return XCTFail("Expected KeychainError.notFound, got \(error)")
            }
        }
    }

    func test_setPIN_rejects_4_digit_PIN() {
        let svc = PINService()
        XCTAssertThrowsError(try svc.setPIN("1234"))
    }
}
#endif
