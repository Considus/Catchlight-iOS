//
//  ConflictRelativeTimeTests.swift
//  CatchlightAppTests
//
//  A saved version's time on the conflict screen is never in the future tense.
//  Another device's clock can run a little ahead, and a fixture saved "now" can
//  land a moment after the formatter's reference date.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

final class ConflictRelativeTimeTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    func testDateOneSecondAhead_readsLikeNow_inEnglish() {
        let nowText = ConflictResolutionView.relativeDate(now, now: now, locale: english)
        let text = ConflictResolutionView.relativeDate(now.addingTimeInterval(1), now: now, locale: english)
        XCTAssertEqual(text, nowText)
        XCTAssertFalse(text.hasPrefix("in "), text)
    }

    func testDateFiveMinutesAhead_readsLikeNow_inEnglish() {
        let nowText = ConflictResolutionView.relativeDate(now, now: now, locale: english)
        let text = ConflictResolutionView.relativeDate(now.addingTimeInterval(300), now: now, locale: english)
        XCTAssertEqual(text, nowText)
        XCTAssertFalse(text.hasPrefix("in "), text)
    }

    func testDateTwoMinutesBefore_stillReadsInThePast() {
        let text = ConflictResolutionView.relativeDate(now.addingTimeInterval(-120), now: now, locale: english)
        XCTAssertTrue(text.contains("ago"), text)
        XCTAssertFalse(text.hasPrefix("in "), text)
    }

    func testDateOneSecondAhead_inGerman_isNotInZeroSeconds() {
        let text = ConflictResolutionView.relativeDate(now.addingTimeInterval(1), now: now, locale: german)
        XCTAssertNotEqual(text, "in 0 Sek.")
        XCTAssertEqual(text, ConflictResolutionView.relativeDate(now, now: now, locale: german))
        XCTAssertFalse(text.hasPrefix("in "), text)
    }
}
#endif
