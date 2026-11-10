//
//  WordmarkTests.swift
//  CatchlightTests (app module)
//
//  The wordmark resolves for every Scene in Light and Dark, and the drawn mark (letters
//  in the text token, the dot of the i in the lit token) matches the brand SVG for that
//  Scene. The reference PNGs were rendered from the SVGs in the brand folder with
//  rsvg-convert at 1034 by 186 over white (Light) or black (Dark).
//

import XCTest
import SwiftUI
@testable import Catchlight

@MainActor
final class WordmarkTests: XCTestCase {

    func testWordmarkAssetsResolve() {
        XCTAssertNotNil(UIImage(named: "catchlight-wordmark-letters"), "letters asset missing")
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            XCTAssertNotNil(UIImage(named: "catchlight-wordmark", in: nil, compatibleWith: traits),
                            "launch wordmark missing for \(style.rawValue)")
        }
    }

    private func render(_ scene: CatchlightScene, dark: Bool) -> CGImage? {
        let view = CatchlightWordmark()
            .frame(width: 1034, height: 186)
            .background(dark ? Color.black : Color.white)
            .environment(\.catchlightScene, scene)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.cgImage
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// Share of pixels that differ from the reference by more than 48 in any channel.
    private func mismatch(_ a: CGImage, _ b: CGImage) -> Double {
        let (x, y) = (rgba(a), rgba(b))
        var bad = 0
        for i in stride(from: 0, to: x.count, by: 4) {
            for c in 0..<3 where abs(Int(x[i + c]) - Int(y[i + c])) > 48 { bad += 1; break }
        }
        return Double(bad) / Double(x.count / 4)
    }

    func testDrawnWordmark_matchesTheBrandSVG_forEveryScene_inLightAndDark() throws {
        for scene in CatchlightScene.allCases {
            for dark in [false, true] {
                let name = "wordmark-\(scene.rawValue)-\(dark ? "dark" : "light")"
                let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "png"), name)
                let reference = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
                let drawn = try XCTUnwrap(render(scene, dark: dark), "no render for \(name)")
                XCTAssertEqual(drawn.width, reference.width, name)
                XCTAssertEqual(drawn.height, reference.height, name)
                XCTAssertLessThan(mismatch(drawn, reference), 0.002, "\(name) differs from the SVG")
            }
        }
    }

    func testTheMeasureCanFail_aWrongSceneDiffers() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "wordmark-jade-light", withExtension: "png"))
        let reference = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        let wrong = try XCTUnwrap(render(.cobalt, dark: false))
        // Letters differ by colour between Scenes in Light, so most ink pixels differ.
        XCTAssertGreaterThan(mismatch(wrong, reference), 0.002)
    }
}
