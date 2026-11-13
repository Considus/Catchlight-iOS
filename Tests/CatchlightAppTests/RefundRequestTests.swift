//
//  RefundRequestTests.swift
//
//  The in-app "Request a refund" flow. Apple's refund sheet is Apple's UI and can't show
//  in a test, so the manager takes the sheet as a closure, and the latest transaction as
//  another, and these tests stand in for both: they don't touch StoreKit at all, so a cold
//  simulator or a slow runner can't change their result.
//
//  The one test that does touch StoreKit, `testRefund_liveStoreKitSession_...`, buys through
//  a StoreKit testing session (the app's Catchlight.storekit) and checks the real lookup.
//

#if canImport(Catchlight)
import XCTest
import StoreKit
import StoreKitTest
@testable import Catchlight

@MainActor
final class RefundRequestTests: XCTestCase {

    private let transactionID: UInt64 = 2_000_000_123

    // MARK: - The flow, with the store and the sheet stood in

    func testRefund_withPurchase_asksAppleAboutThatTransaction_andReportsSubmitted() async {
        var asked: UInt64?
        let outcome = await SubscriptionManager().requestRefund(latestTransactionID: { self.transactionID }) { id in
            asked = id
            return .success
        }
        XCTAssertEqual(outcome, .submitted)
        XCTAssertEqual(asked, transactionID)
    }

    func testRefund_userClosesSheet_reportsCancelled() async {
        let outcome = await SubscriptionManager().requestRefund(latestTransactionID: { self.transactionID }) { _ in .userCancelled }
        XCTAssertEqual(outcome, .cancelled)
    }

    func testRefund_noPurchase_neverOpensSheet_reportsNoPurchase() async {
        var opened = false
        let outcome = await SubscriptionManager().requestRefund(latestTransactionID: { nil }) { _ in
            opened = true
            return .success
        }
        XCTAssertEqual(outcome, .noPurchase)
        XCTAssertFalse(opened)
    }

    func testRefund_appleSaysDuplicate_reportsAlreadyRequested() async {
        let outcome = await SubscriptionManager().requestRefund(latestTransactionID: { self.transactionID }) { _ in
            throw Transaction.RefundRequestError.duplicateRequest
        }
        XCTAssertEqual(outcome, .alreadyRequested)
    }

    func testRefund_appleFails_reportsFailed() async {
        let outcome = await SubscriptionManager().requestRefund(latestTransactionID: { self.transactionID }) { _ in
            throw Transaction.RefundRequestError.failed
        }
        XCTAssertEqual(outcome, .failed)
    }

    func testRefund_unknownError_reportsFailed() async {
        let outcome = await SubscriptionManager().requestRefund(latestTransactionID: { self.transactionID }) { _ in
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertEqual(outcome, .failed)
    }

    // MARK: - The real StoreKit lookup

    /// Buys the Annual product in a StoreKit testing session and asks for a refund with the
    /// manager's real lookup. Waits for a *verified* latest transaction: a transaction
    /// that is present but unverified also reads as "nothing to refund".
    ///
    /// On the first run after a simulator is created or erased, the session's purchase
    /// succeeds but the app's `Transaction.latest` never shows it (measured: 40 seconds,
    /// four retries, a product load first and a set storefront changed nothing), and
    /// StoreKit logs "Error updating Storefront" in the Sandbox environment. The next run
    /// on the same simulator passes at once. On CI (ci.yml passes TEST_RUNNER_CI) that is a
    /// failure with its reason; on a Mac it skips: run again.
    func testRefund_liveStoreKitSession_findsThePurchase_andAsksAboutIt() async throws {
        let config = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Catchlight/Resources/Catchlight.storekit")
        let session = try SKTestSession(contentsOf: config)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        try session.buyProduct(productIdentifier: SubscriptionManager.annualProductID)
        var seen: UInt64?
        for _ in 0..<100 {
            seen = await SubscriptionManager.latestAnnualTransactionID()
            if seen != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let seen else {
            let raw = await Transaction.latest(for: SubscriptionManager.annualProductID)
            let state = raw == nil ? "no transaction" : "a transaction that isn't verified"
            let message = "StoreKit isn't connected to the testing session: after 10 seconds it reports \(state)."
            if ProcessInfo.processInfo.environment["CI"] == "true" {
                XCTFail(message)
                return
            }
            throw XCTSkip(message + " Run again.")
        }

        var asked: UInt64?
        let outcome = await SubscriptionManager().requestRefund { id in
            asked = id
            return .success
        }
        XCTAssertEqual(outcome, .submitted)
        XCTAssertEqual(asked, seen)
    }
}
#endif
