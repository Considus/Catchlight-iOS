//
//  LocalisationPluralTests.swift
//  CatchlightAppTests
//
//  The counts in these strings used to be English grammar built in code
//  ("Take\(n == 1 ? "" : "s")"). They are now one catalog key each with plural
//  variations, so English depends on the catalog's `one`/`other` forms. These pin
//  the English output, including keys that also carry a name before the count.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

final class LocalisationPluralTests: XCTestCase {

    private var english: Locale { Locale(identifier: "en") }

    func testTakeCounts_useSingularForOne() {
        XCTAssertEqual(String(localized: "\(1) Takes need a decision.", locale: english), "1 Take needs a decision.")
        XCTAssertEqual(String(localized: "\(2) Takes need a decision.", locale: english), "2 Takes need a decision.")
        XCTAssertEqual(String(localized: "\(1) Takes changed on another device.", locale: english),
                       "1 Take changed on another device.")
        XCTAssertEqual(String(localized: "\(1) Takes couldn't be verified and were skipped.", locale: english),
                       "1 Take couldn't be verified and was skipped.")
        XCTAssertEqual(String(localized: "Import successful. \(1) Takes added to your timeline.", locale: english),
                       "Import successful. 1 Take added to your timeline.")
        XCTAssertEqual(String(localized: "Import successful. \(3) Takes added.", locale: english),
                       "Import successful. 3 Takes added.")
        XCTAssertEqual(String(localized: "\(1) Takes couldn't be verified and need a choice.", locale: english),
                       "1 Take couldn't be verified and needs a choice.")
        XCTAssertEqual(String(localized: "\(1) Takes not re-uploaded. This device was away too long to rule out deletion elsewhere. Edit a Take to sync it again.", locale: english),
                       "1 Take not re-uploaded. This device was away too long to rule out deletion elsewhere. Edit a Take to sync it again.")
    }

    /// A name before the count: the plural must key on the count, and both values land.
    func testNameAndCount_bothSubstituted() {
        XCTAssertEqual(String(localized: "Link to \("example.com") and \(1) more links", locale: english),
                       "Link to example.com and 1 more link")
        XCTAssertEqual(String(localized: "Link to \("example.com") and \(4) more links", locale: english),
                       "Link to example.com and 4 more links")
        XCTAssertEqual(String(localized: "Email to \("ann at example.com") and \(1) more emails", locale: english),
                       "Email to ann at example.com and 1 more email")
    }
}
#endif
