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

    /// The English table itself, so these hold whatever language the device runs in:
    /// `locale:` alone sets number formatting, not which language's text is loaded.
    private let englishBundle: Bundle = {
        let path = Bundle.main.path(forResource: "en", ofType: "lproj")
        return path.flatMap(Bundle.init(path:)) ?? .main
    }()
    private var english: Locale { Locale(identifier: "en") }

    func testTakeCounts_useSingularForOne() {
        XCTAssertEqual(String(localized: "\(1) Takes need a decision.", bundle: englishBundle, locale: english), "1 Take needs a decision.")
        XCTAssertEqual(String(localized: "\(2) Takes need a decision.", bundle: englishBundle, locale: english), "2 Takes need a decision.")
        XCTAssertEqual(String(localized: "\(1) Takes changed on another device.", bundle: englishBundle, locale: english),
                       "1 Take changed on another device.")
        XCTAssertEqual(String(localized: "\(1) Takes couldn't be verified and were skipped.", bundle: englishBundle, locale: english),
                       "1 Take couldn't be verified and was skipped.")
        XCTAssertEqual(String(localized: "Import successful. \(1) Takes added to your timeline.", bundle: englishBundle, locale: english),
                       "Import successful. 1 Take added to your timeline.")
        XCTAssertEqual(String(localized: "Import successful. \(3) Takes added.", bundle: englishBundle, locale: english),
                       "Import successful. 3 Takes added.")
        XCTAssertEqual(String(localized: "\(1) Takes couldn't be verified and need a choice.", bundle: englishBundle, locale: english),
                       "1 Take couldn't be verified and needs a choice.")
        XCTAssertEqual(String(localized: "\(1) Takes not re-uploaded. This device was away too long to rule out deletion elsewhere. Edit a Take to sync it again.", bundle: englishBundle, locale: english),
                       "1 Take not re-uploaded. This device was away too long to rule out deletion elsewhere. Edit a Take to sync it again.")
    }

    /// A name before the count: the plural must key on the count, and both values land.
    func testNameAndCount_bothSubstituted() {
        XCTAssertEqual(String(localized: "Link to \("example.com") and \(1) more links", bundle: englishBundle, locale: english),
                       "Link to example.com and 1 more link")
        XCTAssertEqual(String(localized: "Link to \("example.com") and \(4) more links", bundle: englishBundle, locale: english),
                       "Link to example.com and 4 more links")
        XCTAssertEqual(String(localized: "Email to \("ann at example.com") and \(1) more emails", bundle: englishBundle, locale: english),
                       "Email to ann at example.com and 1 more email")
    }

    private let frenchBundle: Bundle = {
        let path = Bundle.main.path(forResource: "fr", ofType: "lproj")
        return path.flatMap(Bundle.init(path:)) ?? .main
    }()
    private var french: Locale { Locale(identifier: "fr") }

    /// French takes the singular for 0 as well as 1, unlike English.
    func testFrenchTakeCounts_useSingularForZeroAndOne() {
        XCTAssertEqual(String(localized: "\(0) Takes changed on another device.", bundle: frenchBundle, locale: french),
                       "0 Take modifié sur un autre appareil.")
        XCTAssertEqual(String(localized: "\(1) Takes need a decision.", bundle: frenchBundle, locale: french),
                       "1 Take demande une décision.")
        XCTAssertEqual(String(localized: "\(2) Takes need a decision.", bundle: frenchBundle, locale: french),
                       "2 Takes demandent une décision.")
        XCTAssertEqual(String(localized: "Link to \("example.com") and \(1) more links", bundle: frenchBundle, locale: french),
                       "Lien vers example.com et 1 autre lien")
    }

    /// The trial length has no plural in English ("14-day") but needs one in French,
    /// so the variations exist only in the French table.
    func testFrenchTrialLength_isPlural() {
        XCTAssertEqual(String(localized: "\(1)-week", bundle: frenchBundle, locale: french), "1 semaine")
        XCTAssertEqual(String(localized: "\(14)-day", bundle: frenchBundle, locale: french), "14 jours")
        XCTAssertEqual(String(localized: "\(1)-day", bundle: englishBundle, locale: english), "1-day")
    }
}
#endif
