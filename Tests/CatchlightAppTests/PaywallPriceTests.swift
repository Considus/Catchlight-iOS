//
//  PaywallPriceTests.swift
//
//  The price line never breaks inside the price: on the small iPhone it wrapped as
//  "$14.99/" then "year".
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

final class PaywallPriceTests: XCTestCase {

    func testUnbreakable_putsAWordJoinerAfterTheSlash() {
        XCTAssertEqual(PaywallView.unbreakable("$14.99/year"), "$14.99/\u{2060}year")
    }

    func testUnbreakable_leavesAPriceWithoutASlashAlone() {
        XCTAssertEqual(PaywallView.unbreakable("14,99 € pro Jahr"), "14,99 € pro Jahr")
    }
}
#endif
