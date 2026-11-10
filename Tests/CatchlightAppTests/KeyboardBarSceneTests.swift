//
//  KeyboardBarSceneTests.swift
//  CatchlightTests (app module)
//
//  The two UIKit keyboard bars (search, and the recovery-phrase Restore bar) paint their
//  fade and borders as CGColors, which do not follow traits. Both bars live for the app's
//  lifetime, so each must repaint when the Scene changes, and a bar built before it joins a
//  window must paint that window's Scene once it does.
//

import XCTest
import UIKit
@testable import Catchlight

final class KeyboardBarSceneTests: XCTestCase {

    func testSearchBar_paintsTheWindowsScene_onJoining_andAfterASwitch() throws {
        try withSceneWindow(.jade) { window, defaults in
            let controller = SearchInputController()
            // Built before it is in any window, under another Scene in the same (Dark)
            // appearance, so only the Scene differs when it joins.
            var bar: SearchBarAccessory!
            sceneTraits(.graphite, .dark).performAsCurrent { bar = controller.bar }
            window.addSubview(bar)
            bar.updateTraitsIfNeeded()
            assertSearchBarPaints(bar, .jade, "joining a Jade window")

            SettingsViewModel.SceneChoice.select(.onyx, defaults: defaults)
            bar.updateTraitsIfNeeded()
            assertSearchBarPaints(bar, .onyx, "after switching to Onyx")
        }
    }

    func testRestoreBar_paintsTheWindowsScene_onJoining_andAfterASwitch() throws {
        try withSceneWindow(.jade) { window, defaults in
            var bar: RestoreKeyboardAccessory!
            sceneTraits(.graphite, .dark).performAsCurrent {
                bar = RestoreKeyboardAccessory(onRestore: {}, onBack: {})
            }
            window.addSubview(bar)
            bar.updateTraitsIfNeeded()
            assertPaints(bar, .jade, restoreBarBorders, "joining a Jade window")

            SettingsViewModel.SceneChoice.select(.onyx, defaults: defaults)
            assertPaints(bar, .onyx, restoreBarBorders, "after switching to Onyx")
        }
    }

    // MARK: - Helpers

    /// The search row is a solid strip of the Scene's ground (as rendered by the layer),
    /// and its one bordered view, the field, is outlined with the `outline` token.
    private func assertSearchBarPaints(_ bar: UIView, _ scene: CatchlightScene, _ label: String,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let traits = sceneTraits(scene, .dark)
        let strip = bar.layer.backgroundColor.map { UIColor(cgColor: $0) }
        XCTAssertEqual(strip.map(hex), hex(SceneToken.ground.resolvedColor(with: traits)),
                       "\(label): strip", file: file, line: line)
        let bordered = allViews(in: bar).filter { $0.layer.borderWidth > 0 }
        XCTAssertEqual(bordered.count, 1, "\(label): only the field is outlined", file: file, line: line)
        for view in bordered {
            XCTAssertTrue(view is UITextField, "\(label): \(type(of: view)) is outlined", file: file, line: line)
            let border = view.layer.borderColor.map { UIColor(cgColor: $0) }
            XCTAssertEqual(border.map(hex), hex(SceneToken.outline.resolvedColor(with: traits)),
                           "\(label): field outline", file: file, line: line)
        }
    }
    /// The Restore bar's only bordered button, Back, is outlined with the `outline` token.
    private let restoreBarBorders: (UIView) -> (UIColor, CGFloat) = { _ in (SceneToken.outline, 1) }

    /// The fade's solid stop is the Scene's Dark ground, and every bordered view's border is
    /// the colour `borders` gives for it, in that Scene.
    private func assertPaints(_ bar: UIView, _ scene: CatchlightScene, _ borders: (UIView) -> (UIColor, CGFloat),
                              _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let traits = sceneTraits(scene, .dark)
        let fade = bar.layer.sublayers?.compactMap { $0 as? CAGradientLayer }.first
        let solid = (fade?.colors?.last).map { UIColor(cgColor: $0 as! CGColor) }
        XCTAssertEqual(solid.map(hex), hex(SceneToken.ground.resolvedColor(with: traits)),
                       "\(label): fade", file: file, line: line)

        let bordered = allViews(in: bar).filter { $0.layer.borderWidth > 0 }
        XCTAssertFalse(bordered.isEmpty, "\(label): no bordered views", file: file, line: line)
        for view in bordered {
            let (colour, alpha) = borders(view)
            let expected = colour.resolvedColor(with: traits).withAlphaComponent(alpha)
            let border = view.layer.borderColor.map { UIColor(cgColor: $0) }
            XCTAssertEqual(border.map(hex), hex(expected), "\(label): border of \(type(of: view))", file: file, line: line)
        }
    }

    private func allViews(in view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap(allViews)
    }

    private func hex(_ c: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X@%.2f", Int((r * 255).rounded()), Int((g * 255).rounded()),
                      Int((b * 255).rounded()), a)
    }

    /// A Dark window on the test host's window scene, set to `scene`, with its own defaults
    /// suite. The window scene's Scene is put back afterwards.
    private func withSceneWindow(_ scene: CatchlightScene, _ body: (UIWindow, UserDefaults) throws -> Void) throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = windowScene.traitOverrides[SceneTrait.self]
        let suite = "catchlight.tests.keyboardbar.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: 0, y: 0, width: 400, height: 100)
        window.overrideUserInterfaceStyle = .dark
        window.isHidden = false
        SettingsViewModel.SceneChoice.select(scene, defaults: defaults)
        defer {
            window.isHidden = true
            windowScene.traitOverrides[SceneTrait.self] = previous
            defaults.removePersistentDomain(forName: suite)
        }
        try body(window, defaults)
    }
}
