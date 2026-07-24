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

    private var savedRaw: String?

    override func setUp() {
        super.setUp()
        savedRaw = UserDefaults.standard.string(forKey: SpotlightExposure.defaultsKey)
    }

    override func tearDown() {
        if let savedRaw {
            UserDefaults.standard.set(savedRaw, forKey: SpotlightExposure.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: SpotlightExposure.defaultsKey)
        }
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
            UserDefaults.standard.set(locked.rawValue, forKey: SpotlightExposure.defaultsKey)
            XCTAssertEqual(SpotlightExposure.current, .type,
                           "a pre-lock body level must clamp to Type only, not \(locked)")
        }
    }

    func testCurrent_selectableLevels_roundTripUnchanged() {
        for level in [SpotlightExposure.none, .type] {
            UserDefaults.standard.set(level.rawValue, forKey: SpotlightExposure.defaultsKey)
            XCTAssertEqual(SpotlightExposure.current, level)
        }
    }

    func testCurrent_missingOrGarbageValue_fallsBackToDefault() {
        UserDefaults.standard.removeObject(forKey: SpotlightExposure.defaultsKey)
        XCTAssertEqual(SpotlightExposure.current, .default)
        UserDefaults.standard.set("not-a-level", forKey: SpotlightExposure.defaultsKey)
        XCTAssertEqual(SpotlightExposure.current, .default)
    }
}
#endif
