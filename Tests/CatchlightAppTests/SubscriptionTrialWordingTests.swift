//
//  SubscriptionTrialWordingTests.swift
//
//  The paywall's trial line ("Start your 14-day trial now, …") takes its length
//  from the introductory offer the App Store reports. App Store Connect sets the
//  trial only in weeks: its "2 weeks" arrives as a period of 2 weeks (seen through
//  StoreKit Testing on 2026-11-09). The paywall must still say "14-day".
//  A Debug build's paywall hard-codes "14-day", so only these tests or a Release
//  build show the real wording.
//

#if canImport(Catchlight)
import XCTest
import StoreKit
@testable import Catchlight

final class SubscriptionTrialWordingTests: XCTestCase {

    func testTrialWording_twoWeeksFromConnect_reads14Day() {
        XCTAssertEqual(SubscriptionManager.trialDurationAdjective(value: 2, unit: .week), "14-day")
    }

    func testTrialWording_fourteenDays_reads14Day() {
        XCTAssertEqual(SubscriptionManager.trialDurationAdjective(value: 14, unit: .day), "14-day")
    }

    func testTrialWording_oneMonth_readsOneMonth() {
        XCTAssertEqual(SubscriptionManager.trialDurationAdjective(value: 1, unit: .month), "1-month")
    }
}
#endif
