//
//  WordmarkTests.swift
//  CatchlightTests (app module)
//
//  The wordmark resolves for every Scene in Light and Dark, and the drawn mark (letters
//  in the text token, the dot of the i in the lit token) matches the brand SVG for that
//  Scene. The reference PNGs were rendered from the SVGs in the brand folder with
//  rsvg-convert at 1580 by 283 over white (Light) or black (Dark).
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
            .background(dark ? Color.black : Color.white)
            .environment(\.catchlightScene, scene)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1580 / CatchlightWordmark.width
        return renderer.cgImage
    }

    private func rgba(_ image: CGImage, width w: Int, height h: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// Share of pixels, inside `region` (as fractions of the image), that differ from the
    /// reference by more than 48 in any channel.
    private func mismatch(_ a: CGImage, _ b: CGImage, region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> Double {
        let (x, y) = (rgba(a, width: b.width, height: b.height), rgba(b, width: b.width, height: b.height))
        let w = b.width, h = b.height
        let x0 = Int(region.minX * CGFloat(w)), x1 = Int(region.maxX * CGFloat(w))
        let y0 = Int(region.minY * CGFloat(h)), y1 = Int(region.maxY * CGFloat(h))
        var bad = 0, total = 0
        for row in y0..<y1 {
            for col in x0..<x1 {
                let i = (row * w + col) * 4
                total += 1
                for c in 0..<3 where abs(Int(x[i + c]) - Int(y[i + c])) > 48 { bad += 1; break }
            }
        }
        return Double(bad) / Double(max(total, 1))
    }

    /// The square around the dot of the i, as fractions of the SVG's viewBox.
    private let dotRegion = CGRect(x: (3350 - 150) / 5171.0, y: 0, width: 300 / 5171.0, height: 240 / 927.55)

    func testDrawnWordmark_matchesTheBrandSVG_forEveryScene_inLightAndDark() throws {
        for scene in CatchlightScene.allCases {
            for dark in [false, true] {
                let name = "wordmark-\(scene.rawValue)-\(dark ? "dark" : "light")"
                let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "png"), name)
                let reference = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
                let drawn = try XCTUnwrap(render(scene, dark: dark), "no render for \(name)")
                XCTAssertEqual(drawn.width, reference.width, name)
                XCTAssertEqual(Double(drawn.height), Double(reference.height), accuracy: 1, name)
                XCTAssertLessThan(mismatch(drawn, reference), 0.03, "\(name) differs from the SVG")
                XCTAssertLessThan(mismatch(drawn, reference, region: dotRegion), 0.1, "\(name): the dot is not where the SVG puts it")
            }
        }
    }

    func testTheMeasureCanFail_aWrongSceneDiffers() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "wordmark-jade-light", withExtension: "png"))
        let reference = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        let wrong = try XCTUnwrap(render(.cobalt, dark: false))
        // Letters differ by colour between Scenes in Light, so most ink pixels differ.
        XCTAssertGreaterThan(mismatch(wrong, reference, region: dotRegion), 0.1)
    }
}
