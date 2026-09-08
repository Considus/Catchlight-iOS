//
//  WritingToolsBehaviourTests.swift
//  CatchlightCoreTests
//
//  D-246. The switch itself is trivial; what these guard is the ONE property that
//  matters — that it fails CLOSED. Writing Tools reached the editor by inheritance
//  rather than by choice, so every path that does not explicitly say "on" must
//  resolve to Off, including the paths nobody thought about: a missing key, a value
//  from a future build, a corrupted string.
//

import XCTest
@testable import CatchlightCore

final class WritingToolsBehaviourTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "writing-tools-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// 🚨 The load-bearing assertion. A default of anything but `.off` would send
    /// Take text to Apple for a user who never opened Settings — the opposite of
    /// the reason they installed the app.
    func testDefaultIsOff() {
        XCTAssertEqual(WritingToolsBehaviour.default, .off)
        XCTAssertEqual(WritingToolsBehaviour.current(defaults), .off)
    }

    func testStoredChoiceRoundTrips() {
        for value in WritingToolsBehaviour.allCases {
            defaults.set(value.rawValue, forKey: WritingToolsBehaviour.defaultsKey)
            XCTAssertEqual(WritingToolsBehaviour.current(defaults), value)
        }
    }

    /// An unrecognised value must fail CLOSED. This is the downgrade case: a build
    /// that adds a fourth level, then the user reinstalls an older one. Failing open
    /// there would silently re-enable a feature they had turned off.
    func testUnknownValueFailsClosedToOff() {
        defaults.set("someLevelFromAFutureBuild", forKey: WritingToolsBehaviour.defaultsKey)
        XCTAssertEqual(WritingToolsBehaviour.current(defaults), .off)
    }

    func testEmptyAndGarbageValuesFailClosed() {
        for junk in ["", " ", "OFF", "Inline", "0", "true"] {
            defaults.set(junk, forKey: WritingToolsBehaviour.defaultsKey)
            XCTAssertEqual(WritingToolsBehaviour.current(defaults), .off,
                           "\(junk.debugDescription) must resolve to .off, not open the feature")
        }
    }

    /// Case sensitivity is deliberate: "Inline" is NOT `.inline`. The test above
    /// covers it, and this documents that the raw values are the contract.
    func testRawValuesAreTheStorageContract() {
        XCTAssertEqual(WritingToolsBehaviour.off.rawValue, "off")
        XCTAssertEqual(WritingToolsBehaviour.panel.rawValue, "panel")
        XCTAssertEqual(WritingToolsBehaviour.inline.rawValue, "inline")
    }

    func testAllCasesAreOfferedInOrder() {
        XCTAssertEqual(WritingToolsBehaviour.allCases, [.off, .panel, .inline])
    }

    func testLabelsAreTheSettingsCopy() {
        XCTAssertEqual(WritingToolsBehaviour.off.label, "Off")
        XCTAssertEqual(WritingToolsBehaviour.panel.label, "Panel")
        XCTAssertEqual(WritingToolsBehaviour.inline.label, "Inline")
    }
}
