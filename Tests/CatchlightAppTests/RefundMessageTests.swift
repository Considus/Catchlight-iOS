//
//  RefundMessageTests.swift
//
//  The words Settings shows after a refund request, as Mark approved them on 13 Nov 2026.
//  Closing Apple's sheet says nothing.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

final class RefundMessageTests: XCTestCase {

    func testMessages_areTheApprovedWording() {
        XCTAssertEqual(SettingsView.refundMessage(for: .submitted),
                       "Your request was sent to Apple. Apple decides. Expect an update in 24 to 48 hours.")
        XCTAssertEqual(SettingsView.refundMessage(for: .alreadyRequested),
                       "You've already asked Apple to refund this subscription. Apple's update can take 24 to 48 hours.")
        XCTAssertEqual(SettingsView.refundMessage(for: .noPurchase),
                       "You can't request a refund for this subscription. During a free trial, nothing has been charged.")
        XCTAssertEqual(SettingsView.refundMessage(for: .failed),
                       "Couldn't send the request. Please try again, or request a refund at reportaproblem.apple.com.")
    }

    func testClosingAppleSheet_saysNothing() {
        XCTAssertNil(SettingsView.refundMessage(for: .cancelled))
    }
}
#endif
