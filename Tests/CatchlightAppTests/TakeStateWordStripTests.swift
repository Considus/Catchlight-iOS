//
//  TakeStateWordStripTests.swift
//  CatchlightTests (app module)
//
//  "OVERDUE" (or "SNOOZED") goes in the strip left of the Iris when it fits at 80% or more,
//  along the card's height less 8pt each end and across the strip; otherwise it stays on the
//  time line (owner 2026-11-12). The dark overdue text colour reaches 4.5:1 on every card.
//

import XCTest
import SwiftUI
import UIKit
@testable import Catchlight

final class TakeStateWordStripTests: XCTestCase {

    private let shortCard: CGFloat = 72          // a one-line reminder: the shortest overdue card
    private let strip402: CGFloat = 24, strip375: CGFloat = 20.625

    private func size(_ word: String, _ dts: DynamicTypeSize = .large) -> CGSize {
        TakeStateWordStrip.size(of: word, dynamicTypeSize: dts)
    }

    func testEnglish_fitsAtFullSize_onTheShortestCard() {
        let s = size("Overdue")
        XCTAssertLessThan(s.width, shortCard - 16)
        XCTAssertEqual(TakeStateWordStrip.scale(wordSize: s, cardHeight: shortCard, stripWidth: strip375), 1)
    }

    func testGerman_goesInTheStrip_atAbout82Percent() throws {
        let scale = try XCTUnwrap(TakeStateWordStrip.scale(wordSize: size("Überfällig"), cardHeight: shortCard, stripWidth: strip402))
        XCTAssertEqual(scale, 0.82, accuracy: 0.02)
    }

    func testTurkish_staysOnTheTimeLine_onAShortCard() {
        XCTAssertNil(TakeStateWordStrip.scale(wordSize: size("Süresi geçti"), cardHeight: shortCard, stripWidth: strip402))
    }

    func testLargestText_isTooThick_soTheWordStaysOnTheTimeLine() {
        let s = size("Overdue", .accessibility5)
        XCTAssertGreaterThan(s.height, strip402 / TakeStateWordStrip.minimumScale)
        XCTAssertNil(TakeStateWordStrip.scale(wordSize: s, cardHeight: 400, stripWidth: strip402))
    }

    func testEdges_exactly80PercentFits_justUnderDoesNot() {
        let word = CGSize(width: 100, height: 10)
        XCTAssertEqual(TakeStateWordStrip.scale(wordSize: word, cardHeight: 96, stripWidth: 30), 0.8)
        XCTAssertNil(TakeStateWordStrip.scale(wordSize: word, cardHeight: 95.9, stripWidth: 30))
        XCTAssertNil(TakeStateWordStrip.scale(wordSize: CGSize(width: 10, height: 30), cardHeight: 200, stripWidth: 23.9))
        XCTAssertNil(TakeStateWordStrip.scale(wordSize: word, cardHeight: 0, stripWidth: 30))
    }

    // MARK: - Colour

    func testOverdueText_isE17070InDark_andB82E2EInLight() {
        XCTAssertEqual(hex(Color.ckTextOverdue, .cobalt, .dark), "#E17070")
        XCTAssertEqual(hex(Color.ckTextOverdue, .cobalt, .light), "#B82E2E")
        XCTAssertEqual(hex(Color.ckCardOverdueBorder, .cobalt, .dark), "#DB5252", "the border is unchanged")
    }

    func testOverdueText_reaches4_5to1_onEveryCardColour() {
        for scene in CatchlightScene.allCases {
            for style in [UIUserInterfaceStyle.dark, .light] {
                for (name, surface) in [("card", Color.ckSurface), ("raised", Color.ckCardObieSurface)] {
                    let r = ratio(Color.ckTextOverdue, surface, scene, style)
                    XCTAssertGreaterThanOrEqual(r, 4.5, "\(scene) \(style == .dark ? "Dark" : "Light") \(name): \(r)")
                }
            }
        }
    }

    // MARK: - Helpers

    private func rgb(_ color: Color, _ scene: CatchlightScene, _ style: UIUserInterfaceStyle) -> (CGFloat, CGFloat, CGFloat) {
        var env = EnvironmentValues()
        env.colorScheme = style == .dark ? .dark : .light
        env.catchlightScene = scene
        let c = UIColor(Color(color.resolve(in: env)))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    private func hex(_ color: Color, _ scene: CatchlightScene, _ style: UIUserInterfaceStyle) -> String {
        let (r, g, b) = rgb(color, scene, style)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    private func ratio(_ a: Color, _ b: Color, _ scene: CatchlightScene, _ style: UIUserInterfaceStyle) -> CGFloat {
        func lum(_ c: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
            func ch(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * ch(c.0) + 0.7152 * ch(c.1) + 0.0722 * ch(c.2)
        }
        let la = lum(rgb(a, scene, style)), lb = lum(rgb(b, scene, style))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
