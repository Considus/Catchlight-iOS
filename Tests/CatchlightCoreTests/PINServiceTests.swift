//
//  PINServiceTests.swift
//  CatchlightCoreTests — Task 3.12, revised for the 2026-06-10 remediation
//
//  Covers PINPolicy, the set → verify → reset round trip, and the PERSISTED
//  lockout counter (the failed-attempt count now lives in the Keychain so a
//  force-quit cannot reset it; `verify` refuses attempts once locked out).
//
//  ISOLATION: every PINService here is constructed with a DEDICATED TEST
//  SERVICE string, so the suite can never clobber a real user's PIN slots —
//  the previous suite called `reset()` against the production service.
//
//  PINService lives in the iOS app target and writes to the device Keychain, so
//  these tests are gated by `#if canImport(Catchlight)` — they run inside the
//  iOS test bundle. Under `swift test` on macOS the Core tests run unchanged.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

final class PINServiceTests: XCTestCase {

    /// Test-only Keychain service — NEVER the production `KeychainConfig.service`.
    private static let testService = "com.considus.catchlight.tests"

    private func makeService() -> PINService {
        // accessGroup nil: an explicit keychain access group requires the
        // keychain-sharing entitlement, which the unsigned simulator test host
        // lacks (SecItemAdd → errSecMissingEntitlement, -34018). Test items
        // live in the host app's default group instead.
        PINService(service: Self.testService, accessGroup: nil)
    }

    override func setUp() {
        super.setUp()
        makeService().reset()   // start from clean test slots
    }

    override func tearDown() {
        makeService().reset()   // leave the test slots clean
        super.tearDown()
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
        let svc = makeService()
        try svc.setPIN("136912")
        XCTAssertTrue(try svc.verify("136912"))
        XCTAssertEqual(svc.failedAttempts, 0)
    }

    func test_setPIN_then_verify_wrong_returns_false_and_increments() throws {
        let svc = makeService()
        try svc.setPIN("136912")
        XCTAssertFalse(try svc.verify("000000"))
        XCTAssertEqual(svc.failedAttempts, 1)
    }

    func test_successfulVerify_resetsFailedAttempts() throws {
        let svc = makeService()
        try svc.setPIN("136912")
        XCTAssertFalse(try svc.verify("000000"))
        XCTAssertFalse(try svc.verify("111111"))
        XCTAssertEqual(svc.failedAttempts, 2)
        XCTAssertTrue(try svc.verify("136912"))
        XCTAssertEqual(svc.failedAttempts, 0, "a correct PIN must zero the counter")
    }

    func test_setPIN_replaces_previous_PIN() throws {
        let svc = makeService()
        try svc.setPIN("136912")
        try svc.setPIN("246810")
        XCTAssertFalse(try svc.verify("136912"))
        XCTAssertTrue(try svc.verify("246810"))
    }

    func test_reset_clears_PIN() throws {
        let svc = makeService()
        try svc.setPIN("136912")
        svc.reset()
        XCTAssertThrowsError(try svc.verify("136912")) { error in
            // notFound is what we expect once the hash/salt slots are gone.
            guard case KeychainError.notFound = error else {
                return XCTFail("Expected KeychainError.notFound, got \(error)")
            }
        }
    }

    func test_setPIN_rejects_4_digit_PIN() {
        let svc = makeService()
        XCTAssertThrowsError(try svc.setPIN("1234"))
    }

    // MARK: - Lockout (persisted counter, 2026-06-10)

    /// After `maxFailedAttempts` consecutive failures, `verify` refuses further
    /// attempts — even with the CORRECT PIN — until reset via mnemonic recovery.
    func test_lockout_afterMaxFailures_refusesEvenCorrectPIN() throws {
        let svc = makeService()
        try svc.setPIN("136912")

        for _ in 0..<PINPolicy.maxFailedAttempts {
            XCTAssertFalse(try svc.verify("000000"))
        }
        XCTAssertTrue(svc.isLockedOut)
        XCTAssertEqual(svc.failedAttempts, PINPolicy.maxFailedAttempts)

        XCTAssertFalse(try svc.verify("136912"),
                       "verify must refuse attempts once locked out — even the correct PIN")
        XCTAssertEqual(svc.failedAttempts, PINPolicy.maxFailedAttempts,
                       "refused attempts must not keep growing the counter")
    }

    /// The failure counter is PERSISTED in the Keychain: a fresh PINService
    /// instance over the same service still sees the lockout (a force-quit no
    /// longer resets the brute-force defence).
    func test_lockout_counterSurvivesNewServiceInstance() throws {
        let first = makeService()
        try first.setPIN("136912")
        for _ in 0..<PINPolicy.maxFailedAttempts {
            XCTAssertFalse(try first.verify("000000"))
        }

        let second = makeService()   // simulates an app relaunch
        XCTAssertEqual(second.failedAttempts, PINPolicy.maxFailedAttempts)
        XCTAssertTrue(second.isLockedOut)
        XCTAssertFalse(try second.verify("136912"))
    }

    func test_failedAttempts_persistAcrossInstances_belowLockout() throws {
        let first = makeService()
        try first.setPIN("136912")
        XCTAssertFalse(try first.verify("000000"))
        XCTAssertFalse(try first.verify("999999"))

        let second = makeService()
        XCTAssertEqual(second.failedAttempts, 2)
        XCTAssertFalse(second.isLockedOut)
        XCTAssertTrue(try second.verify("136912"))
        XCTAssertEqual(second.failedAttempts, 0)
    }

    /// `reset()` clears the counter along with the PIN — setting a new PIN
    /// afterwards starts from a clean slate.
    func test_reset_clearsLockoutCounter() throws {
        let svc = makeService()
        try svc.setPIN("136912")
        for _ in 0..<PINPolicy.maxFailedAttempts {
            _ = try svc.verify("000000")
        }
        XCTAssertTrue(svc.isLockedOut)

        svc.reset()
        XCTAssertEqual(svc.failedAttempts, 0)
        XCTAssertFalse(svc.isLockedOut)

        try svc.setPIN("246810")
        XCTAssertTrue(try svc.verify("246810"))
    }
}
#endif
