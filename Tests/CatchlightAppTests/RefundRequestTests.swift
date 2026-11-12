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

    /// Buys the Annual product, then waits until StoreKit reports it: the transaction
    /// reaches `Transaction.latest` a moment after the purchase on a cold simulator.
    private func subscribe() async throws {
        try session.buyProduct(productIdentifier: SubscriptionManager.annualProductID)
        for _ in 0..<50 {
            if await Transaction.latest(for: SubscriptionManager.annualProductID) != nil { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("the purchase never reached Transaction.latest")
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
