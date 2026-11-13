//
//  RefundRequestTests.swift
//
//  The in-app "Request a refund" flow. A StoreKit testing session (the app's
//  Catchlight.storekit) supplies a real purchase; the refund sheet itself is
//  Apple's UI and can't show in a test, so the manager takes the sheet as a
//  closure and the tests stand in for what Apple's sheet returns.
//

#if canImport(Catchlight)
import XCTest
import StoreKit
import StoreKitTest
@testable import Catchlight

@MainActor
final class RefundRequestTests: XCTestCase {

    private var session: SKTestSession!

    override func setUp() async throws {
        // The app's own configuration, read from the repo (it is not in the test bundle).
        let config = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Catchlight/Resources/Catchlight.storekit")
        session = try SKTestSession(contentsOf: config)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
    }

    /// Buys the Annual product and waits until the app's StoreKit reports it.
    ///
    /// On the first run after a simulator is created or erased, the session's purchase
    /// succeeds (it returns a transaction) but the app's `Transaction.latest` never shows
    /// it, even after 40 seconds, and StoreKit logs "Error updating Storefront" in the
    /// Sandbox environment. The next run on the same simulator passes at once. Waiting
    /// can't fix that, so the test says so and skips instead of failing as a refund bug.
    private func subscribe() async throws {
        try session.buyProduct(productIdentifier: SubscriptionManager.annualProductID)
        for _ in 0..<50 {
            if await Transaction.latest(for: SubscriptionManager.annualProductID) != nil { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw XCTSkip("StoreKit isn't connected to the testing session yet (first run on a new simulator). Run again.")
    }

    func testRefund_withPurchase_asksAppleAboutThatTransaction_andReportsSubmitted() async throws {
        try await subscribe()
        var asked: UInt64?
        let outcome = await SubscriptionManager().requestRefund { id in
            asked = id
            return .success
        }
        XCTAssertEqual(outcome, .submitted)
        let latest = await Transaction.latest(for: SubscriptionManager.annualProductID)
        guard case .verified(let txn) = latest else { return XCTFail("no verified transaction") }
        XCTAssertEqual(asked, txn.id)
    }

    func testRefund_userClosesSheet_reportsCancelled() async throws {
        try await subscribe()
        let outcome = await SubscriptionManager().requestRefund { _ in .userCancelled }
        XCTAssertEqual(outcome, .cancelled)
    }

    func testRefund_noPurchase_neverOpensSheet_reportsNoPurchase() async {
        var opened = false
        let outcome = await SubscriptionManager().requestRefund { _ in
            opened = true
            return .success
        }
        XCTAssertEqual(outcome, .noPurchase)
        XCTAssertFalse(opened)
    }

    func testRefund_appleSaysDuplicate_reportsAlreadyRequested() async throws {
        try await subscribe()
        let outcome = await SubscriptionManager().requestRefund { _ in throw Transaction.RefundRequestError.duplicateRequest }
        XCTAssertEqual(outcome, .alreadyRequested)
    }

    func testRefund_appleFails_reportsFailed() async throws {
        try await subscribe()
        let outcome = await SubscriptionManager().requestRefund { _ in throw Transaction.RefundRequestError.failed }
        XCTAssertEqual(outcome, .failed)
    }

    func testRefund_unknownError_reportsFailed() async throws {
        try await subscribe()
        let outcome = await SubscriptionManager().requestRefund { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertEqual(outcome, .failed)
    }
}
#endif
