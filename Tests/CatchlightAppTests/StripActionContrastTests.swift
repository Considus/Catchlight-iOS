//
//  StripActionContrastTests.swift
//  CatchlightTests (app module)
//
//  The action words on the Dailies strips ("Dismiss", "Review", "Turn on", "Export",
//  "Subscribe", "Export now") reach 4.5:1 against their own band, in every Scene, Dark and
//  Light. A band is its colour tinted over the page (`ground`) at the strength the strip uses
//  (`NoticeStripBand`).
//

import XCTest
import UIKit
@testable import Catchlight

final class StripActionContrastTests: XCTestCase {

    private let styles: [UIUserInterfaceStyle] = [.dark, .light]

    /// The word, its colour, the band's colour and the band's strength.
    private func strips(dark: Bool) -> [(String, UIColor, UIColor, Double)] {
        [
            ("Dismiss on an error strip", UITheme.ruby, UITheme.ruby, NoticeStripBand.ruby),
            ("Export now on the missing-phrase banner", SceneToken.accentText, UITheme.ruby,
             NoticeStripBand.missingPhrase(dark: dark)),
            ("Review, Turn on, Export and Subscribe on an accent strip", SceneToken.accentText,
             SceneToken.accent, NoticeStripBand.accent),
        ]
    }

    func testEveryStripActionWord_reaches4_5to1_onItsBand_inEveryScene() {
        var pairs = 0
        for scene in CatchlightScene.allCases {
            for style in styles {
                pairs += 1
                let traits = sceneTraits(scene, style)
                let ground = rgb(SceneToken.ground, traits)
                for (word, fg, band, strength) in strips(dark: style == .dark) {
                    let bandOnPage = over(rgb(band, traits), strength, ground)
                    let r = ratio(rgb(fg, traits), bandOnPage)
                    XCTAssertGreaterThanOrEqual(r, 4.5, "\(word), \(scene.rawValue) \(style == .dark ? "Dark" : "Light"): "
                                                + String(format: "%.2f", r) + ":1")
                }
            }
        }
        XCTAssertEqual(pairs, 10, "five Scenes, Dark and Light")
    }

    /// The measure itself: black on white is 21:1, and a word on its own colour at full
    /// strength is 1:1, so a failing pair can show.
    func testTheMeasure_knownPairs() {
        XCTAssertEqual(ratio((0, 0, 0), (1, 1, 1)), 21, accuracy: 0.01)
        let red = (0.86, 0.32, 0.32)
        XCTAssertEqual(ratio(red, over(red, 1, (1, 1, 1))), 1, accuracy: 0.001)
    }

    // MARK: Helpers

    private typealias RGB = (Double, Double, Double)

    private func rgb(_ color: UIColor, _ traits: UITraitCollection) -> RGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    /// `top` at `alpha` over an opaque `bottom`, as the screen composites it.
    private func over(_ top: RGB, _ alpha: Double, _ bottom: RGB) -> RGB {
        (alpha * top.0 + (1 - alpha) * bottom.0,
         alpha * top.1 + (1 - alpha) * bottom.1,
         alpha * top.2 + (1 - alpha) * bottom.2)
    }

    private func luminance(_ c: RGB) -> Double {
        func ch(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(c.0) + 0.7152 * ch(c.1) + 0.0722 * ch(c.2)
    }

    private func ratio(_ a: RGB, _ b: RGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
