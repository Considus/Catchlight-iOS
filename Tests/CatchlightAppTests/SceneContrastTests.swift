//
//  SceneContrastTests.swift
//  CatchlightTests (app module)
//
//  Every Scene, in Dark and Light, measured on the surfaces a card or the page can be
//  (ground, card, raised). Text, muted and faint text reach 4.5:1, with faint below muted.
//  Field outlines and lit marks are shapes, so they reach 3:1 (WCAG 1.4.11). Unlit Iris
//  lights are deliberately softer, at 2:1 on every surface including `surface`. The
//  foreground on an accent fill reaches 4.5:1. The accent also reaches 3:1 as a line,
//  except Graphite Light, whose yellow accent is fill-only by design.
//

import XCTest
import UIKit
@testable import Catchlight

final class SceneContrastTests: XCTestCase {

    private let surfaces: [(String, UIColor)] = [
        ("ground", SceneToken.ground), ("card", SceneToken.card), ("raised", SceneToken.raised)
    ]
    private let styles: [UIUserInterfaceStyle] = [.dark, .light]

    func testText_reaches4_5to1_onEverySurface() {
        forEverySurface { label, surface, t in
            assertRatio(SceneToken.text, surface, t, 4.5, "text on \(label)")
        }
    }

    func testMutedAndFaintText_reach4_5to1_andFaintSitsBelowMuted() {
        forEverySurface { label, surface, t in
            let muted = ratio(SceneToken.muted, surface, t), faint = ratio(SceneToken.faint, surface, t)
            XCTAssertGreaterThanOrEqual(muted, 4.5, "muted on \(label): \(muted)")
            XCTAssertGreaterThanOrEqual(faint, 4.5, "faint on \(label): \(faint)")
            XCTAssertLessThan(faint, muted, "faint must recede below muted on \(label)")
        }
    }

    func testFieldOutline_reaches3to1_onEverySurface() {
        forEverySurface { label, surface, t in
            assertRatio(SceneToken.outline, surface, t, 3.0, "outline on \(label)")
        }
    }

    func testUnlitLight_reaches2to1_onEverySurfaceIncludingSurface() {
        let all = surfaces + [("surface", SceneToken.surface)]
        for scene in CatchlightScene.allCases {
            for style in styles {
                for (surfaceName, surface) in all {
                    assertRatio(SceneToken.unlit, surface, sceneTraits(scene, style), 2.0,
                                "unlit on \(surfaceName), \(name(scene, style))")
                }
            }
        }
    }

    func testLit_reaches3to1_onEverySurface() {
        forEverySurface { label, surface, t in
            assertRatio(SceneToken.lit, surface, t, 3.0, "lit on \(label)")
        }
    }

    func testOnAccent_reaches4_5to1_onTheAccentFill() {
        for scene in CatchlightScene.allCases {
            for style in styles {
                let t = sceneTraits(scene, style)
                assertRatio(SceneToken.onAccent, SceneToken.accent, t, 4.5, "onAccent on accent, \(name(scene, style))")
            }
        }
    }

    /// Graphite Light's accent fails as a line on its light surfaces, so it is used only as
    /// a fill (checked above). Every other Scene's accent also works as a line.
    func testAccentAsALine_reaches3to1_exceptGraphiteLightWhichIsFillOnly() {
        forEverySurface(skipping: (.graphite, .light)) { label, surface, t in
            assertRatio(SceneToken.accent, surface, t, 3.0, "accent on \(label)")
        }
    }

    func testDoneTextAndPlaceholder_useFaint() {
        for scene in CatchlightScene.allCases {
            for style in styles {
                let t = sceneTraits(scene, style)
                XCTAssertEqual(UITheme.textComplete.resolvedColor(with: t), SceneToken.faint.resolvedColor(with: t))
                XCTAssertEqual(UITheme.placeholder.resolvedColor(with: t), SceneToken.faint.resolvedColor(with: t))
            }
        }
    }

    // MARK: - Helpers

    private func forEverySurface(skipping skip: (CatchlightScene, UIUserInterfaceStyle)? = nil,
                                 _ body: (String, UIColor, UITraitCollection) -> Void) {
        for scene in CatchlightScene.allCases {
            for style in styles where !(skip?.0 == scene && skip?.1 == style) {
                for (surfaceName, surface) in surfaces {
                    body("\(surfaceName), \(name(scene, style))", surface, sceneTraits(scene, style))
                }
            }
        }
    }

    private func name(_ scene: CatchlightScene, _ style: UIUserInterfaceStyle) -> String {
        "\(scene.rawValue) \(style == .dark ? "Dark" : "Light")"
    }

    private func assertRatio(_ fg: UIColor, _ bg: UIColor, _ t: UITraitCollection, _ minimum: Double, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let r = ratio(fg, bg, t)
        XCTAssertGreaterThanOrEqual(r, minimum, "\(label): \(String(format: "%.2f", r)):1", file: file, line: line)
    }

    private func ratio(_ a: UIColor, _ b: UIColor, _ t: UITraitCollection) -> Double {
        let la = luminance(a.resolvedColor(with: t)), lb = luminance(b.resolvedColor(with: t))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func luminance(_ c: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func ch(_ v: CGFloat) -> Double { let v = Double(v); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
    }
}
