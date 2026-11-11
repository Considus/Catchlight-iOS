//
//  LightStatusBarInstallTests.swift
//  CatchlightAppTests
//
//  The light status bar subclass is installed once on the root view controller. An observer
//  (KVO) that wraps the root afterwards must not make it look like someone else's class,
//  or the style stops following the screens.
//

import XCTest
import UIKit
@testable import Catchlight

@MainActor
final class LightStatusBarInstallTests: XCTestCase {

    private final class Root: UIViewController {}

    func testInstallsOnce_thenReportsAlready() {
        let root = Root()
        XCTAssertEqual(LightStatusBar.install(on: root), .installed)
        XCTAssertEqual(LightStatusBar.install(on: root), .already)
    }

    func testAnObserverAddedAfterInstalling_stillCountsAsOurs() {
        let root = Root()
        XCTAssertEqual(LightStatusBar.install(on: root), .installed)
        let observation = root.observe(\.title) { _, _ in }
        defer { observation.invalidate() }
        XCTAssertEqual(LightStatusBar.install(on: root), .already,
                       "a KVO wrap over our subclass was taken for someone else's class")
    }

    func testAnObserverAddedBeforeInstalling_isLeftAlone() {
        let root = Root()
        let observation = root.observe(\.title) { _, _ in }
        defer { observation.invalidate() }
        XCTAssertEqual(LightStatusBar.install(on: root), .refused)
    }
}
