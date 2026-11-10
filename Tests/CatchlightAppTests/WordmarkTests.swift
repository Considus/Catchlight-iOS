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
    /// reference by more than 48 in any channel. With `edge` a pixel only counts when it
    /// also differs from every neighbour within `edge` pixels of the reference, so a
    /// shared anti-aliased edge that lands half a pixel apart is not a mismatch but ink
    /// in the wrong place still is.
    private func mismatch(_ x: [UInt8], _ y: [UInt8], width w: Int, height h: Int, edge: Int = 0,
                          region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> Double {
        let x0 = Int(region.minX * CGFloat(w)), x1 = Int(region.maxX * CGFloat(w))
        let y0 = Int(region.minY * CGFloat(h)), y1 = Int(region.maxY * CGFloat(h))
        func close(_ i: Int, _ j: Int) -> Bool { (0..<3).allSatisfy { abs(Int(x[i + $0]) - Int(y[j + $0])) <= 48 } }
        var bad = 0, total = 0
        for row in y0..<y1 {
            for col in x0..<x1 {
                total += 1
                let i = (row * w + col) * 4
                var matched = false
                search: for dr in -edge...edge {
                    for dc in -edge...edge {
                        let r = row + dr, c = col + dc
                        guard r >= 0, r < h, c >= 0, c < w else { continue }
                        if close(i, (r * w + c) * 4) { matched = true; break search }
                    }
                }
                if !matched { bad += 1 }
            }
        }
        return Double(bad) / Double(max(total, 1))
    }

    private func mismatch(_ a: CGImage, _ b: CGImage, edge: Int = 0,
                          region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> Double {
        mismatch(rgba(a, width: b.width, height: b.height), rgba(b, width: b.width, height: b.height),
                 width: b.width, height: b.height, edge: edge, region: region)
    }

    /// The square around the dot of the i, as fractions of the SVG's viewBox.
    private let dotRegion = CGRect(x: (3350 - 150) / 5171.0, y: 0, width: 300 / 5171.0, height: 240 / 927.55)

    /// The one tolerance, and why. The drawn mark is 1580 by 284 pixels (28.33pt at 55.7
    /// scale rounds up) and the reference is the SVG rasterised at 1580 by 283, so every
    /// edge sits within a pixel of the reference but not on it. Measured over all ten
    /// Scene and appearance pairs: counting a pixel only when no reference pixel within
    /// one pixel matches it, the mismatch is 0.28% to 0.58%, from anti-aliased edges
    /// alone. Strict (same pixel) it is 1.1% to 1.4%, which is the same edges. A dot
    /// moved 200 SVG units (61 pixels) measures 1.5% to 1.8% by the same count, so 1%
    /// separates the two.
    private let tolerance = 0.01

    func testDrawnWordmark_matchesTheBrandSVG_forEveryScene_inLightAndDark() throws {
        for scene in CatchlightScene.allCases {
            for dark in [false, true] {
                let name = "wordmark-\(scene.rawValue)-\(dark ? "dark" : "light")"
                let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "png"), name)
                let reference = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
                let drawn = try XCTUnwrap(render(scene, dark: dark), "no render for \(name)")
                XCTAssertEqual(drawn.width, reference.width, name)
                XCTAssertEqual(Double(drawn.height), Double(reference.height), accuracy: 1, name)
                XCTAssertLessThan(mismatch(drawn, reference, edge: 1), tolerance, "\(name) differs from the SVG")
            }
        }
    }

    /// The reference with the dot of the i moved right by `units` SVG units.
    private func movedDot(_ ref: [UInt8], width w: Int, height h: Int, units: Double) -> [UInt8] {
        var out = ref
        let bg = Array(ref[0..<4])
        let x0 = Int(dotRegion.minX * CGFloat(w)), x1 = Int(dotRegion.maxX * CGFloat(w))
        let y1 = Int(dotRegion.maxY * CGFloat(h))
        let shift = Int((units / 5171.0 * Double(w)).rounded())
        for r in 0..<y1 { for c in x0..<x1 { for k in 0..<4 { out[(r * w + c) * 4 + k] = bg[k] } } }
        for r in 0..<y1 { for c in x0..<x1 where c + shift < w {
            for k in 0..<4 { out[(r * w + c + shift) * 4 + k] = ref[(r * w + c) * 4 + k] }
        } }
        return out
    }

    /// The tolerance must still catch a dot 200 SVG units out of place.
    func testTheTolerance_stillFailsADotMoved200Units() throws {
        for dark in [false, true] {
            let name = "wordmark-cobalt-\(dark ? "dark" : "light")"
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "png"))
            let reference = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
            let drawn = try XCTUnwrap(render(.cobalt, dark: dark))
            let (w, h) = (reference.width, reference.height)
            let moved = movedDot(rgba(reference, width: w, height: h), width: w, height: h, units: 200)
            XCTAssertGreaterThan(mismatch(rgba(drawn, width: w, height: h), moved, width: w, height: h, edge: 1), tolerance, name)
        }
    }

    func testTheMeasureCanFail_aWrongSceneDiffers() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "wordmark-jade-light", withExtension: "png"))
        let reference = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        let wrong = try XCTUnwrap(render(.cobalt, dark: false))
        // Letters differ by colour between Scenes in Light, so most ink pixels differ.
        XCTAssertGreaterThan(mismatch(wrong, reference, edge: 1), tolerance)
    }

    /// The gap above and below the wordmark is at least the height of its "h".
    func testClearSpace_isAtLeastTheHHeight() {
        XCTAssertGreaterThanOrEqual(CatchlightWordmark.iconGap, CatchlightWordmark.hHeight)
    }

    /// The launch screen's background is Cobalt's ground, in Light and in Dark.
    func testLaunchBackground_isCobaltsGround() throws {
        for dark in [false, true] {
            let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
            let color = try XCTUnwrap(UIColor(named: "ck-background", in: Bundle.main, compatibleWith: traits))
            var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
            color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
            let hex = CatchlightScene.cobalt.palette(dark: dark).ground
            XCTAssertEqual(r, CGFloat((hex >> 16) & 0xFF) / 255, accuracy: 0.002, "red, dark \(dark)")
            XCTAssertEqual(g, CGFloat((hex >> 8) & 0xFF) / 255, accuracy: 0.002, "green, dark \(dark)")
            XCTAssertEqual(b, CGFloat(hex & 0xFF) / 255, accuracy: 0.002, "blue, dark \(dark)")
        }
    }
}
