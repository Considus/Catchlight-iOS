//
//  AppIconChoiceTests.swift
//  CatchlightAppTests
//
//  The App icon row's names must match the icons the build actually ships: a name iOS
//  doesn't know makes `setAlternateIconName` fail and the row does nothing.
//

import XCTest
@testable import Catchlight

final class AppIconChoiceTests: XCTestCase {

    func testCobaltIsTheMainIcon() {
        XCTAssertNil(AppIconChoice.iconName(for: .cobalt))
        XCTAssertEqual(AppIconChoice.scene(forIconName: nil), .cobalt)
    }

    func testEverySceneRoundTrips() {
        for scene in CatchlightScene.allCases {
            XCTAssertEqual(AppIconChoice.scene(forIconName: AppIconChoice.iconName(for: scene)), scene)
        }
    }

    func testUnknownIconNameReadsAsCobalt() {
        XCTAssertEqual(AppIconChoice.scene(forIconName: "AppIcon-Retired"), .cobalt)
    }

    /// The built app's Info.plist lists Cobalt as the main icon and every other Scene's
    /// icon as an alternate, and nothing more.
    func testBuiltAppListsEveryIcon() throws {
        let icons = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let primary = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
        XCTAssertEqual(primary["CFBundleIconName"] as? String, "AppIcon")

        let alternates = try XCTUnwrap(icons["CFBundleAlternateIcons"] as? [String: Any])
        let expected = Set(CatchlightScene.allCases.compactMap(AppIconChoice.iconName(for:)))
        XCTAssertEqual(expected.count, CatchlightScene.allCases.count - 1)
        XCTAssertEqual(Set(alternates.keys), expected)
    }
}
