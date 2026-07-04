//
//  LocationEditorNameGuardTests.swift
//  CatchlightAppTests — 2026-07-04 testability follow-up to the mid-point remediation
//
//  Pins the reverse-geocode name-clobber guard fixed in PR #102: a fresh location
//  fix must only auto-name a place the user hasn't named, or the slow geocode
//  overwrote e.g. "Home" with the street address (and `writeBack` persisted it).
//  The decision was factored out of the SwiftUI `onChange` into the pure
//  `LocationEditor.shouldAdoptGeocodedName` so it is testable without the view.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

final class LocationEditorNameGuardTests: XCTestCase {

    /// Adopt the geocoded name only when the field is empty or still the auto
    /// placeholder this editor writes on a fresh pin.
    func testAdoptsGeocodedName_whenEmptyOrPlaceholder() {
        XCTAssertTrue(LocationEditor.shouldAdoptGeocodedName(currentName: ""))
        XCTAssertTrue(LocationEditor.shouldAdoptGeocodedName(
            currentName: LocationEditor.currentLocationPlaceholder))
    }

    /// A user-chosen name must survive a re-pin's reverse geocode (the bug).
    func testKeepsUserName_whenNamed() {
        XCTAssertFalse(LocationEditor.shouldAdoptGeocodedName(currentName: "Home"),
                       "re-pinning must not rename 'Home' to a street address")
        XCTAssertFalse(LocationEditor.shouldAdoptGeocodedName(currentName: "12 Acacia Avenue"))
    }
}
#endif
