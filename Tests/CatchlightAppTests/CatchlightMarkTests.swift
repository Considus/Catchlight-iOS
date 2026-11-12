import XCTest
import SwiftUI
@testable import Catchlight

/// The icon art matches the brand's app icon geometry, and the bare mark's ring fills its box.
final class CatchlightMarkTests: XCTestCase {

    func testTile_scalesTheSixtyFourGridToTheBox() {
        let p = CatchlightMark.placement(style: .tile, size: 72)
        XCTAssertEqual(p.scale, 72.0 / 64.0, accuracy: 1e-9)
        XCTAssertEqual(p.origin, .zero)
    }

    func testBare_ringOuterEdgeFillsTheBox() {
        let size: CGFloat = 72
        let p = CatchlightMark.placement(style: .bare, size: size)
        let c = CatchlightMark.Art.ringCentre, r = CatchlightMark.Art.ringOuterDiameter / 2
        XCTAssertEqual(p.origin.x + (c.x - r) * p.scale, 0, accuracy: 1e-9)
        XCTAssertEqual(p.origin.x + (c.x + r) * p.scale, size, accuracy: 1e-9)
        XCTAssertEqual(p.origin.y + (c.y - r) * p.scale, 0, accuracy: 1e-9)
        XCTAssertEqual(p.origin.y + (c.y + r) * p.scale, size, accuracy: 1e-9)
    }

    func testArt_matchesTheBrandIconNumbers() {
        // Brand_System/svg/app-icon/cobalt/cobalt-icon-default.svg
        XCTAssertEqual(CatchlightMark.Art.ringCentre, CGPoint(x: 32, y: 33))
        XCTAssertEqual(CatchlightMark.Art.ringRadius, 15)
        XCTAssertEqual(CatchlightMark.Art.ringStroke, 7.5)
        XCTAssertEqual(CatchlightMark.Art.dotCentre, CGPoint(x: 43.6, y: 21.4))
        XCTAssertEqual(CatchlightMark.Art.dotRadius, 5.1)
        XCTAssertEqual(CatchlightMark.Art.notchRadius, 8.1)
        XCTAssertEqual(CatchlightMark.Art.ringOuterDiameter, 37.5)
    }

    /// Pixels: the bare mark draws ring white on the field and the dot in the icon-dot colour.
    @MainActor func testBare_rendersRingAndDotInTheTokens() throws {
        let renderer = ImageRenderer(content:
            CatchlightMark(style: .bare, size: 72).environment(\.colorScheme, .light))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        let cg = try XCTUnwrap(image.cgImage)
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            var px = [UInt8](repeating: 0, count: 4)
            let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
            return px
        }
        // Left of the ring's middle: white. Centre of the ring: clear. Dot: pink (R high, G mid).
        let left = pixel(5, 36)
        XCTAssertGreaterThan(left[3], 250); XCTAssertGreaterThan(left[0], 240); XCTAssertGreaterThan(left[1], 240)
        XCTAssertEqual(pixel(36, 36)[3], 0)
        let p = CatchlightMark.placement(style: .bare, size: 72)
        let dot = pixel(Int(p.origin.x + 43.6 * p.scale), Int(p.origin.y + 21.4 * p.scale))
        XCTAssertGreaterThan(dot[0], 240); XCTAssertLessThan(dot[1], 180); XCTAssertGreaterThan(dot[2], 180)
    }
}
