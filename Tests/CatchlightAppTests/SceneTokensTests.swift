//
//  SceneTokensTests.swift
//  CatchlightTests (app module)
//
//  The five Scenes are generated from `design/tokens.json`. These tests read that JSON
//  and check the generated Swift against it: every Scene, in both appearances, resolves
//  each app role to the source hex. They also hold the stored-choice rules (a missing or
//  unknown value means Cobalt) and that choosing a Scene re-resolves the same colour in
//  the same view. `SceneUITests` proves it on screen in SwiftUI. The generated file's
//  freshness against the generator is `scripts/design/gen_scene_tokens.py --check`.
//

import XCTest
import UIKit
import SwiftUI
@testable import Catchlight

final class SceneTokensTests: XCTestCase {

    /// The app roles the generator emits, each with the token that carries it.
    private let roles: [(String, UIColor)] = [
        ("ground", SceneToken.ground), ("surface", SceneToken.surface), ("card", SceneToken.card),
        ("raised", SceneToken.raised), ("line", SceneToken.line), ("outline", SceneToken.outline),
        ("text", SceneToken.text), ("muted", SceneToken.muted), ("faint", SceneToken.faint),
        ("accent", SceneToken.accent), ("accentText", SceneToken.accentText),
        ("onAccent", SceneToken.onAccent), ("lit", SceneToken.lit), ("unlit", SceneToken.unlit),
        ("field", SceneToken.field), ("onField", SceneToken.onField),
        ("fieldMuted", SceneToken.fieldMuted), ("iconDot", SceneToken.iconDot)
    ]

    private struct Source: Decodable {
        struct Scene: Decodable {
            let name: String
            let dark: [String: String]
            let light: [String: String]
        }
        let `default`: String
        let scenes: [String: Scene]
    }

    private func source() throws -> Source {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("design/tokens.json")
        return try JSONDecoder().decode(Source.self, from: Data(contentsOf: url))
    }

    // MARK: - Generated values match the source

    func testEveryScene_resolvesEveryAppRole_toTheSourceHex() throws {
        let json = try source()
        XCTAssertEqual(Set(json.scenes.keys), Set(CatchlightScene.allCases.map(\.rawValue)),
                       "the generated Scenes differ from the JSON's")
        for scene in CatchlightScene.allCases {
            let entry = try XCTUnwrap(json.scenes[scene.rawValue])
            for (style, palette) in [(UIUserInterfaceStyle.dark, entry.dark), (.light, entry.light)] {
                for (role, token) in roles {
                    let expected = try XCTUnwrap(palette[role], "\(scene) has no \(role) in the JSON")
                    XCTAssertEqual(hex(token, scene, style), expected.uppercased(),
                                   "\(scene.rawValue) \(style == .dark ? "Dark" : "Light") \(role)")
                }
            }
        }
    }

    func testSceneNames_matchTheSource() throws {
        let json = try source()
        for scene in CatchlightScene.allCases {
            XCTAssertEqual(scene.name, json.scenes[scene.rawValue]?.name)
        }
    }

    func testDefault_isCobalt_andMatchesTheSource() throws {
        XCTAssertEqual(CatchlightScene.default, .cobalt)
        XCTAssertEqual(CatchlightScene.default.rawValue, try source().default)
        XCTAssertEqual(SceneTrait.defaultValue, .cobalt)
    }

    // MARK: - The stored choice

    func testStoredChoice_missingOrUnknownMeansCobalt_andAKnownValueIsRead() throws {
        let suite = "catchlight.tests.scene.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(SettingsViewModel.SceneChoice.current(defaults), .cobalt, "missing")
        defaults.set("vermilion", forKey: SettingsViewModel.SceneChoice.defaultsKey)
        XCTAssertEqual(SettingsViewModel.SceneChoice.current(defaults), .cobalt, "unknown")
        defaults.set("jade", forKey: SettingsViewModel.SceneChoice.defaultsKey)
        XCTAssertEqual(SettingsViewModel.SceneChoice.current(defaults), .jade, "known")
    }

    /// With no store named, the choice is read from the app group, where the share sheet
    /// (and later the widgets) can read it too. The app's own standard defaults don't count.
    func testStoredChoice_isReadFromTheAppGroup_andFallsBackToCobalt() throws {
        let group = try XCTUnwrap(UserDefaults(suiteName: AppGroup.identifier))
        let key = SettingsViewModel.SceneChoice.defaultsKey
        let previousGroup = group.object(forKey: key), previousStandard = UserDefaults.standard.object(forKey: key)
        defer {
            group.set(previousGroup, forKey: key)
            UserDefaults.standard.set(previousStandard, forKey: key)
        }

        group.removeObject(forKey: key)
        UserDefaults.standard.set("onyx", forKey: key)
        XCTAssertEqual(SettingsViewModel.SceneChoice.current(), .cobalt, "missing from the app group")
        group.set("vermilion", forKey: key)
        XCTAssertEqual(SettingsViewModel.SceneChoice.current(), .cobalt, "unknown in the app group")
        group.set("jade", forKey: key)
        XCTAssertEqual(SettingsViewModel.SceneChoice.current(), .jade, "known in the app group")
        XCTAssertEqual(CatchlightScene.stored(), .jade, "the share sheet's reader agrees")
    }

    // MARK: - Switching re-resolves in place

    /// Choosing a Scene stores it and sets it on the app's window scene, pushing the trait
    /// through at once. A UIKit view's existing `SceneToken.card` background then resolves
    /// to the new Scene's card with no further prompt: the same view and the same colour
    /// object, nothing rebuilt.
    func testSelectingAScene_reResolvesAUIKitColour_onTheSameView() throws {
        try withSceneWindow { window, defaults in
            let view = UIView(frame: window.bounds)
            view.backgroundColor = SceneToken.card
            window.addSubview(view)

            SettingsViewModel.SceneChoice.select(.cobalt, defaults: defaults)
            let before = try XCTUnwrap(view.backgroundColor?.resolvedColor(with: view.traitCollection))
            SettingsViewModel.SceneChoice.select(.jade, defaults: defaults)
            let after = try XCTUnwrap(view.backgroundColor?.resolvedColor(with: view.traitCollection))

            XCTAssertEqual(hex(before), "#131840", "Cobalt Dark card")
            XCTAssertEqual(hex(after), "#13201A", "Jade Dark card")
            XCTAssertTrue(view.backgroundColor === SceneToken.card, "the same colour object")
            XCTAssertTrue(view.superview === window, "the same view")
            XCTAssertEqual(defaults.string(forKey: SettingsViewModel.SceneChoice.defaultsKey), "jade")
        }
    }

    /// SwiftUI's `ck*` colours resolve from the environment's Scene, which SwiftUI bridges
    /// from `SceneTrait` on every hosting controller and tracks, so a Scene change repaints them.
    func testSwiftUIColour_resolvesFromTheEnvironmentsScene() {
        var env = EnvironmentValues()
        env.colorScheme = .dark
        env.catchlightScene = .cobalt
        let cobalt = Color.ckSurface.resolve(in: env)
        env.catchlightScene = .jade
        let jade = Color.ckSurface.resolve(in: env)
        XCTAssertEqual(hex(UIColor(Color(cobalt))), "#131840")
        XCTAssertEqual(hex(UIColor(Color(jade))), "#13201A")
        env.colorScheme = .light
        XCTAssertEqual(hex(UIColor(Color(Color.ckSurface.resolve(in: env)))), "#FFFFFF", "Jade Light card")
    }

    // MARK: - Helpers

    private func hex(_ token: UIColor, _ scene: CatchlightScene, _ style: UIUserInterfaceStyle) -> String {
        hex(token.resolvedColor(with: sceneTraits(scene, style)))
    }

    private func hex(_ c: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// A Dark window on the test host's window scene, with its own defaults suite. The
    /// window scene's Scene is put back afterwards.
    private func withSceneWindow(_ body: (UIWindow, UserDefaults) throws -> Void) throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = windowScene.traitOverrides[SceneTrait.self]
        let suite = "catchlight.tests.scene.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        window.overrideUserInterfaceStyle = .dark
        window.isHidden = false
        defer {
            window.isHidden = true
            windowScene.traitOverrides[SceneTrait.self] = previous
            defaults.removePersistentDomain(forName: suite)
        }
        try body(window, defaults)
    }
}
