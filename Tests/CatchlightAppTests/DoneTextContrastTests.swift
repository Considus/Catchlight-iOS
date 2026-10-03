//
//  DoneTextContrastTests.swift
//  CatchlightTests (app module)
//
//  The receded "done" grey (`UITheme.textComplete`, behind `ckTextComplete`) is text,
//  so it has to clear WCAG 2.x 1.4.3's 4.5:1 on every surface it sits on, in both
//  scenes (owner 2026-10-03). The backgrounds are the palette's published hexes,
//  written out here rather than read back from the theme, so a change to either side
//  is caught.
//

import XCTest
import UIKit
@testable import Catchlight

final class DoneTextContrastTests: XCTestCase {

    private let minimum = 4.5   // WCAG 2.x 1.4.3, normal-size text

    func testDoneTextClearsMinimumInNight() {
        let done = resolved(UITheme.textComplete, .dark)
        assertContrast(done, on: 0x1C1A16, "Night card (Dusk)")
        assertContrast(done, on: 0x2D2921, "Night Obie card")
        assertContrast(done, on: 0x0F0E0C, "Night page (Ink)")
    }

    func testDoneTextClearsMinimumInDaylight() {
        let done = resolved(UITheme.textComplete, .light)
        assertContrast(done, on: 0xFFFFFF, "Daylight card (White)")
        assertContrast(done, on: 0xFBF8F3, "Daylight Obie card")
        assertContrast(done, on: 0xF7F4EF, "Daylight page (Paper)")
    }

    // MARK: - Helpers

    private func resolved(_ color: UIColor, _ style: UIUserInterfaceStyle) -> UIColor {
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    private func assertContrast(_ fg: UIColor, on bgHex: UInt32, _ label: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let bg = rgb(bgHex)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(fg.getRed(&r, green: &g, blue: &b, alpha: &a), "\(label): not an RGB colour", file: file, line: line)
        // An alpha grey is what the eye sees once composited onto its background.
        let shown = (r * a + bg.0 * (1 - a), g * a + bg.1 * (1 - a), b * a + bg.2 * (1 - a))
        let ratio = contrast(shown, bg)
        XCTAssertGreaterThanOrEqual(ratio, minimum, "\(label): done text is \(String(format: "%.2f", ratio)):1", file: file, line: line)
    }

    private func rgb(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
        (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
    }

    private func luminance(_ c: (CGFloat, CGFloat, CGFloat)) -> Double {
        func channel(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.0) + 0.7152 * channel(c.1) + 0.0722 * channel(c.2)
    }

    private func contrast(_ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat)) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
