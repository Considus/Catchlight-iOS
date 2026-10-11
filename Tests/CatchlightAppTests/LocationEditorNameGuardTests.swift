//
//  LocationEditorNameGuardTests.swift
//  CatchlightAppTests — 2026-07-04 testability follow-up to the mid-point remediation
//
//  Pins the reverse-geocode name-clobber guard fixed in PR #102: a fresh location
//  fix must only auto-name a place the user hasn't named, or the slow geocode
//  overwrote e.g. "Home" with the street address (and `writeBack` persisted it).
//  The decision was factored out of the SwiftUI `onChange` into the pure
//  `LocationEditor.shouldReplaceName` so it is testable without the view.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

final class LocationEditorNameGuardTests: XCTestCase {

    /// Adopt the geocoded name only when the field is empty or still the auto
    /// placeholder this editor writes on a fresh pin.
    func testAdoptsGeocodedName_whenEmptyOrPlaceholder() {
        XCTAssertTrue(LocationEditor.shouldReplaceName(currentName: ""))
        XCTAssertTrue(LocationEditor.shouldReplaceName(
            currentName: LocationEditor.currentLocationPlaceholder))
    }

    /// The placeholder is saved as the place name, so a pin dropped under one language
    /// must still read as unnamed after the device language changes.
    func testAdoptsGeocodedName_forPlaceholderInEveryBundledLanguage() {
        XCTAssertTrue(LocationEditor.shouldReplaceName(currentName: "Current location"))
        for language in Bundle.main.localizations {
            guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { continue }
            let saved = bundle.localizedString(forKey: "Current location", value: nil, table: nil)
            XCTAssertTrue(LocationEditor.shouldReplaceName(currentName: saved),
                          "a pin saved under \(language) as \"\(saved)\" must still be replaceable")
        }
    }

    /// A user-chosen name must survive a re-pin's reverse geocode (the bug).
    func testKeepsUserName_whenNamed() {
        XCTAssertFalse(LocationEditor.shouldReplaceName(currentName: "Home"),
                       "re-pinning must not rename 'Home' to a street address")
        XCTAssertFalse(LocationEditor.shouldReplaceName(currentName: "12 Acacia Avenue"))
    }

    /// A name this editor filled in itself (a reverse-geocoded address, or a search result's
    /// title) follows the next place picked: "Use current location", then a search for
    /// somewhere else, used to leave the first place's address on the new one.
    func testReplacesTheNameThisEditorFilledIn_whenAnotherPlaceIsPicked() {
        XCTAssertTrue(LocationEditor.shouldReplaceName(currentName: "12 Acacia Avenue",
                                                       lastAutoName: "12 Acacia Avenue"),
                      "the current location's address must give way to the place picked next")
        XCTAssertTrue(LocationEditor.shouldReplaceName(currentName: "Tesco Extra",
                                                       lastAutoName: "Tesco Extra"),
                      "a first search result's name must give way to a second")
    }

    /// Once the user has typed over the filled-in name, it is theirs.
    func testKeepsAName_theUserTypedOverTheFilledInOne() {
        XCTAssertFalse(LocationEditor.shouldReplaceName(currentName: "Gym",
                                                        lastAutoName: "12 Acacia Avenue"))
    }
}
#endif
