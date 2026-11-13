//
//  DailiesDateTests.swift
//  CatchlightAppTests
//
//  The date beside "Dailies" carries an ordinal in English ("12th") and French ("1er", on the
//  1st only), with the letters raised; every other language shows exactly what it did before.
//

import XCTest
@testable import Catchlight

final class DailiesDateTests: XCTestCase {

    /// Noon on the day, in the time zone the formatter uses, so the day can't slip.
    private func day(_ d: Int, month: Int = 11, year: Int = 2026) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = d; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func plain(_ date: Date, _ id: String) -> String {
        DailiesHeading.dateParts(for: date, locale: Locale(identifier: id)).plain
    }

    func testUS_putsTheOrdinalAfterTheMonth() {
        let parts = DailiesHeading.dateParts(for: day(12), locale: Locale(identifier: "en_US"))
        XCTAssertEqual(parts.plain, "Thursday, November 12th")
        XCTAssertEqual(parts.day, "12")
        XCTAssertEqual(parts.suffix, "th")
    }

    func testUK_putsTheOrdinalBeforeTheMonth() {
        XCTAssertEqual(plain(day(12), "en_GB"), "Thursday 12th November")
        XCTAssertEqual(plain(day(30, month: 9), "en_GB"), "Wednesday 30th September")
    }

    func testAustralia_hasTheOrdinal() {
        let parts = DailiesHeading.dateParts(for: day(12), locale: Locale(identifier: "en_AU"))
        XCTAssertEqual(parts.suffix, "th")
        XCTAssertTrue(parts.plain.contains("12th"), parts.plain)
    }

    func testEnglishSuffixes_includingTheTeens() {
        let expected: [Int: String] = [1: "st", 2: "nd", 3: "rd", 4: "th", 11: "th", 12: "th", 13: "th",
                                       21: "st", 22: "nd", 23: "rd", 24: "th", 30: "th", 31: "st"]
        for (d, suffix) in expected {
            XCTAssertEqual(DailiesHeading.ordinalSuffix(day: d, locale: Locale(identifier: "en_GB")), suffix, "day \(d)")
        }
    }

    func testFrench_1er_onTheFirstOnly() {
        XCTAssertEqual(plain(day(1), "fr_FR"), "dimanche 1er novembre")
        XCTAssertEqual(plain(day(12), "fr_FR"), "jeudi 12 novembre")
        XCTAssertEqual(DailiesHeading.dateParts(for: day(12), locale: Locale(identifier: "fr_FR")).suffix, "")
    }

    /// Every other language the app ships in shows the system's own date, unchanged.
    func testOtherLanguages_areUnchanged() {
        let others = Bundle(for: AppModel.self).localizations
            .filter { !$0.hasPrefix("en") && !$0.hasPrefix("fr") && $0 != "Base" }
        XCTAssertGreaterThan(others.count, 10, "Found only \(others) in the app bundle")
        for id in others {
            let locale = Locale(identifier: id)
            for d in [1, 2, 3, 12, 31] {
                let date = day(d, month: d == 31 ? 12 : 11)
                let system = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
                let parts = DailiesHeading.dateParts(for: date, locale: locale)
                XCTAssertEqual(parts.plain, system, "\(id) day \(d)")
                XCTAssertEqual(parts.suffix, "", "\(id) day \(d)")
            }
        }
    }
}
