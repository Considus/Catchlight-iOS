//
//  SpotlightExposureLockTests.swift
//  CatchlightAppTests — the 2026-07-24 body-level lock
//
//  Since iOS 17, global Spotlight surfaces only title/displayName matches for
//  third-party items (Apple FB17330079, verified on-device 2026-07-24), so the
//  two body-indexing exposure levels are LOCKED in Settings and any previously
//  persisted body level clamps to `.type`. These tests pin the clamp and the
//  offered set, so re-enabling is a deliberate act (flip `isSelectable`), not
//  an accident.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight
@testable import CatchlightCore

final class SpotlightExposureLockTests: XCTestCase {

    /// An isolated suite per test, so nothing here reads or writes the simulator's real
    /// Settings.
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "catchlight.tests.spotlight.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testOfferedLevels_areNoneAndTypeOnly() {
        XCTAssertTrue(SpotlightExposure.none.isSelectable)
        XCTAssertTrue(SpotlightExposure.type.isSelectable)
        XCTAssertFalse(SpotlightExposure.firstLine.isSelectable)
        XCTAssertFalse(SpotlightExposure.all.isSelectable)
    }

    func testCurrent_persistedBodyLevel_clampsToType() {
        for locked in [SpotlightExposure.firstLine, .all] {
            defaults.set(locked.rawValue, forKey: SpotlightExposure.defaultsKey)
            XCTAssertEqual(SpotlightExposure.current(defaults), .type,
                           "a pre-lock body level must clamp to Type only, not \(locked)")
        }
    }

    func testCurrent_selectableLevels_roundTripUnchanged() {
        for level in [SpotlightExposure.none, .type] {
            defaults.set(level.rawValue, forKey: SpotlightExposure.defaultsKey)
            XCTAssertEqual(SpotlightExposure.current(defaults), level)
        }
    }

    func testCurrent_missingOrGarbageValue_fallsBackToDefault() {
        defaults.removeObject(forKey: SpotlightExposure.defaultsKey)
        XCTAssertEqual(SpotlightExposure.current(defaults), .default)
        defaults.set("not-a-level", forKey: SpotlightExposure.defaultsKey)
        XCTAssertEqual(SpotlightExposure.current(defaults), .default)
    }
}
#endif
