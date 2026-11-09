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
            assertPaints(bar, .jade, borders: SceneToken.accentText, alpha: 0.55, "joining a Jade window")

            SettingsViewModel.SceneChoice.select(.onyx, defaults: defaults)
            assertPaints(bar, .onyx, borders: SceneToken.accentText, alpha: 0.55, "after switching to Onyx")
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
            assertPaints(bar, .jade, borders: SceneToken.text, alpha: 0.4, "joining a Jade window")

            SettingsViewModel.SceneChoice.select(.onyx, defaults: defaults)
            assertPaints(bar, .onyx, borders: SceneToken.text, alpha: 0.4, "after switching to Onyx")
        }
    }

    // MARK: - Helpers

    /// The fade's solid stop is the Scene's Dark ground, and every bordered button's
    /// border is `borders` at `alpha` in that Scene.
    private func assertPaints(_ bar: UIView, _ scene: CatchlightScene, borders: UIColor, alpha: CGFloat,
                              _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let traits = sceneTraits(scene, .dark)
        let fade = bar.layer.sublayers?.compactMap { $0 as? CAGradientLayer }.first
        let solid = (fade?.colors?.last).map { UIColor(cgColor: $0 as! CGColor) }
        XCTAssertEqual(solid.map(hex), hex(SceneToken.ground.resolvedColor(with: traits)),
                       "\(label): fade", file: file, line: line)

        let expected = borders.resolvedColor(with: traits).withAlphaComponent(alpha)
        let bordered = allViews(in: bar).filter { $0.layer.borderWidth > 0 }
        XCTAssertFalse(bordered.isEmpty, "\(label): no bordered views", file: file, line: line)
        for view in bordered {
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
