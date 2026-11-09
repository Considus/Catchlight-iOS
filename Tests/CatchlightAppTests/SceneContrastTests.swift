//
//  SceneContrastTests.swift
//  CatchlightTests (app module)
//
//  Unlit Iris lights are shapes, so they reach 3:1 (WCAG 1.4.11) on every surface a card
//  or the page can be, and the receding `faint` text still reaches 4.5:1 while sitting
//  below `muted`. Measured against the Scene tokens in both appearances.
//

import XCTest
import UIKit
@testable import Catchlight

final class SceneContrastTests: XCTestCase {

    private let surfaces: [(String, UIColor)] = [
        ("ground", SceneToken.ground), ("card", SceneToken.card), ("raised", SceneToken.raised)
    ]

    func testUnlitLightOutline_reaches3to1_onEverySurface() {
        for style in [UIUserInterfaceStyle.dark, .light] {
            for (name, surface) in surfaces {
                let ratio = contrast(SceneToken.outline, surface, style)
                XCTAssertGreaterThanOrEqual(ratio, 3.0, "outline on \(name), \(style == .dark ? "Dark" : "Light"): \(ratio)")
            }
        }
    }

    func testFaintText_reaches4_5to1_andSitsBelowMuted() {
        for style in [UIUserInterfaceStyle.dark, .light] {
            for (name, surface) in surfaces {
                let faint = contrast(SceneToken.faint, surface, style)
                XCTAssertGreaterThanOrEqual(faint, 4.5, "faint on \(name): \(faint)")
                XCTAssertLessThan(faint, contrast(SceneToken.muted, surface, style), "faint must recede below muted on \(name)")
            }
        }
    }

    func testDoneTextAndPlaceholder_useFaint() {
        for style in [UIUserInterfaceStyle.dark, .light] {
            let t = UITraitCollection(userInterfaceStyle: style)
            XCTAssertEqual(UITheme.textComplete.resolvedColor(with: t), SceneToken.faint.resolvedColor(with: t))
            XCTAssertEqual(UITheme.placeholder.resolvedColor(with: t), SceneToken.faint.resolvedColor(with: t))
        }
    }

    // MARK: - Helpers

    private func contrast(_ a: UIColor, _ b: UIColor, _ style: UIUserInterfaceStyle) -> Double {
        let t = UITraitCollection(userInterfaceStyle: style)
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
