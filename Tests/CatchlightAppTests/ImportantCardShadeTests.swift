//
//  ImportantCardShadeTests.swift
//  CatchlightTests (app module)
//
//  An Important Take's card has its own shade in Daylight, where `raised` is the same white as
//  a plain card, and keeps `raised` in Dark (owner 2026-11-12, art director's values).
//  The Obie takes the same shade, with its Iris matching its card; an Important Take's Iris is
//  the plain card colour. Important cards have a mid edge between line and lit.
//

import XCTest
import SwiftUI
@testable import Catchlight
import CatchlightCore

final class ImportantCardShadeTests: XCTestCase {

    /// The values Mark picked, written out here rather than read from the JSON, so a token
    /// edit that moves one fails.
    private let daylight: [CatchlightScene: String] = [
        .cobalt: "#E8EAF5", .graphite: "#E2E4E7", .onyx: "#EBEEF2", .jade: "#E5F2E7", .tanzanite: "#E3EEFA"
    ]

    /// The Important edge, 55% of the way from line to lit (art director 2026-11-12).
    private let edgeLight: [CatchlightScene: String] = [
        .cobalt: "#7886EB", .graphite: "#6A6C6F", .onyx: "#74A2B2", .jade: "#738E81", .tanzanite: "#8084D0"
    ]
    private let edgeDark: [CatchlightScene: String] = [
        .cobalt: "#9E6FA6", .graphite: "#A28E44", .onyx: "#79939C", .jade: "#669678", .tanzanite: "#A18385"
    ]

    func testEveryScene_hasItsImportantEdge() {
        for scene in CatchlightScene.allCases {
            XCTAssertEqual(hex(Color.ckCardImportantBorder, scene, .light), edgeLight[scene], "\(scene) Daylight")
            XCTAssertEqual(hex(Color.ckCardImportantBorder, scene, .dark), edgeDark[scene], "\(scene) Dark")
        }
    }

    /// The Obie's daylight card is the Important shade (owner 2026-11-12), read from the same
    /// token, and its Iris matches its card.
    func testObie_takesTheImportantShade_andItsIrisMatches() {
        let obie = Take(blocks: [.textLine("b")], isObie: true)
        for scene in CatchlightScene.allCases {
            XCTAssertEqual(hex(TakeCardStyle(take: obie, scheme: .light).surface, scene, .light), daylight[scene], "\(scene)")
            XCTAssertEqual(hex(IrisView.fill(for: obie), scene, .light), daylight[scene], "\(scene) Iris")
        }
    }

    func testEveryScene_hasItsDaylightImportantShade() {
        XCTAssertEqual(Set(daylight.keys), Set(CatchlightScene.allCases))
        for scene in CatchlightScene.allCases {
            XCTAssertEqual(hex(Color.ckCardImportantSurface, scene, .light), daylight[scene], "\(scene) Daylight")
        }
    }

    func testDaylightImportant_differsFromThePlainCard() {
        for scene in CatchlightScene.allCases {
            XCTAssertNotEqual(hex(Color.ckCardImportantSurface, scene, .light), hex(Color.ckSurface, scene, .light), "\(scene)")
        }
    }

    func testDark_keepsRaised() {
        for scene in CatchlightScene.allCases {
            XCTAssertEqual(hex(Color.ckCardImportantSurface, scene, .dark), hex(Color.ckCardObieSurface, scene, .dark), "\(scene)")
        }
    }

    func testCardSurface_importantObieAndPlain() {
        let important = Take(blocks: [.textLine("a")], isImportant: true)
        let obie = Take(blocks: [.textLine("b")], isObie: true)
        let plain = Take(blocks: [.textLine("c")])
        for scene in CatchlightScene.allCases {
            for (style, scheme) in [(UIUserInterfaceStyle.light, ColorScheme.light), (.dark, .dark)] {
                XCTAssertEqual(hex(TakeCardStyle(take: important, scheme: scheme).surface, scene, style),
                               hex(Color.ckCardImportantSurface, scene, style), "\(scene) \(style) Important")
                XCTAssertEqual(hex(TakeCardStyle(take: obie, scheme: scheme).surface, scene, style),
                               hex(Color.ckCardImportantSurface, scene, style), "\(scene) \(style) Obie")
                XCTAssertEqual(hex(TakeCardStyle(take: plain, scheme: scheme).surface, scene, style),
                               hex(Color.ckSurface, scene, style), "\(scene) \(style) plain")
            }
        }
    }

    /// A former Obie is drawn as any other Important Take: the shade and the Important edge.
    func testFormerObie_drawsAsImportant() {
        var take = Take(blocks: [.textLine("a")], isObie: true)
        take.isObie = false
        let style = TakeCardStyle(take: take, scheme: .light)
        XCTAssertEqual(hex(style.surface, .jade, .light), daylight[.jade])
        XCTAssertEqual(hex(style.border, .jade, .light), edgeLight[.jade])
    }

    func testIrisFill_isThePlainCard_onImportant_andTheObiesCardOnTheObie() {
        let important = Take(blocks: [.textLine("a")], isImportant: true)
        let obie = Take(blocks: [.textLine("b")], isObie: true)
        for scene in CatchlightScene.allCases {
            for style in [UIUserInterfaceStyle.light, .dark] {
                XCTAssertEqual(hex(IrisView.fill(for: important), scene, style), hex(Color.ckCard, scene, style), "\(scene) \(style)")
                XCTAssertEqual(hex(IrisView.fill(for: obie), scene, style), hex(Color.ckCardImportantSurface, scene, style), "\(scene) \(style)")
            }
        }
    }

    private func hex(_ color: Color, _ scene: CatchlightScene, _ style: UIUserInterfaceStyle) -> String {
        var env = EnvironmentValues()
        env.colorScheme = style == .dark ? .dark : .light
        env.catchlightScene = scene
        let c = UIColor(Color(color.resolve(in: env)))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
