//
//  HeldCardIrisUITests.swift
//  CatchlightUITests
//
//  Pressing and holding a Take card lifts it into the long-press menu's preview. The Iris
//  sits inside the card's top-left, so if it is not part of the lifted view the preview
//  covers it and the Iris vanishes while the menu shows (owner, on device, slice 1).
//  The test samples the Iris's outline ring at rest (proving the probe sees a drawn Iris)
//  and again with the menu up. The lift scales the card slightly (measured about 2% on the
//  iPhone 17e), so each screenshot's card edges are found from its pixels and the Iris is
//  placed `irisInset` in from those, scaled with the card.
//

import XCTest

final class HeldCardIrisUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testHeldCard_keepsItsIris_whileTheMenuShows() throws {
        let app = launchAppForUITesting()
        let row = takeRow(in: app, withLabelStarting: "Buy film")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Seeded Take not on the timeline")
        sleep(1) // let the timeline settle before reading frames

        let card = row.frame

        let rest = XCUIScreen.main.screenshot()
        attach(rest, "held-card-iris-rest")
        let restCard = drawnCardFrame(near: card, in: rest.image)
        let restEdges = irisRingShares(of: irisFrame(in: restCard, resting: card), in: rest.image)
        note("rest", card: restCard, edges: restEdges)
        XCTAssertGreaterThanOrEqual(restEdges.min() ?? 0, 0.5,
                                    "Probe cannot see the Iris at rest: \(restEdges)")

        // Hold the card clear of the Iris, so the card's menu (not the Iris's Obie press) answers.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Delete Take"].waitForExistence(timeout: 5),
                      "Long-press menu did not appear")
        sleep(1) // let the lift animation finish

        let held = XCUIScreen.main.screenshot()
        attach(held, "held-card-iris-menu")
        let heldCard = drawnCardFrame(near: card, in: held.image)
        let heldEdges = irisRingShares(of: irisFrame(in: heldCard, resting: card), in: held.image)
        note("held", card: heldCard, edges: heldEdges)
        XCTAssertGreaterThanOrEqual(heldEdges.min() ?? 0, 0.5,
                                    "The Iris is not drawn on the held card: weakest edge shows only \(Int((heldEdges.min() ?? 0) * 100))% of the ring \(heldEdges)")
    }

    /// The Iris is drawn `irisInset` (14) in from the card's top and leading edges, 44 square,
    /// scaled with the card when the lift enlarges it.
    private func irisFrame(in drawn: CGRect, resting: CGRect) -> CGRect {
        let k = drawn.width / resting.width
        return CGRect(x: drawn.minX + 14 * k, y: drawn.minY + 14 * k, width: 44 * k, height: 44 * k)
    }

    /// The card as drawn in `image`: its fill is sampled inside the card's lower right, clear of
    /// text and the Iris. The side edges are found by walking in from 30pt outside the resting
    /// frame until the pixel matches that fill; the top and bottom by walking out from the
    /// middle of that clear strip until it stops matching (the neighbouring cards above and
    /// below share the fill, so an outside-in walk would stop on them).
    private func drawnCardFrame(near card: CGRect, in image: UIImage) -> CGRect {
        guard let cg = image.cgImage else { return card }
        let scale = CGFloat(cg.width) / image.size.width
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return card }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        func rgb(_ x: CGFloat, _ y: CGFloat) -> (Int, Int, Int) {
            let cx = min(max(Int(x * scale), 0), w - 1), cy = min(max(Int(y * scale), 0), h - 1)
            let i = (cy * w + cx) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
        let fill = rgb(card.maxX - 30, card.maxY - 12)
        func isFill(_ x: CGFloat, _ y: CGFloat) -> Bool {
            let p = rgb(x, y)
            return abs(p.0 - fill.0) + abs(p.1 - fill.1) + abs(p.2 - fill.2) <= 12
        }
        let step = 1 / scale
        var minX = card.minX - 30; while minX < card.midX, !isFill(minX, card.midY + 10) { minX += step }
        var maxX = card.maxX + 30; while maxX > card.midX, !isFill(maxX, card.midY + 10) { maxX -= step }
        var minY = card.midY; while minY > card.minY - 30, isFill(card.maxX - 30, minY - step) { minY -= step }
        var maxY = card.midY; while maxY < card.maxY + 30, isFill(card.maxX - 30, maxY + step) { maxY += step }
        // A plain note's card now has a quiet `line` edge (0.75pt), which is not the fill, so the
        // walks above stop just inside it: measured 1.0pt in on each side at 3x. The card's own
        // frame includes that edge, so the found frame is grown back out by it.
        let edge: CGFloat = 1.0
        return CGRect(x: minX - edge, y: minY - edge, width: maxX - minX + 2 * edge, height: maxY - minY + 2 * edge)
    }

    private func attach(_ shot: XCUIScreenshot, _ name: String) {
        let a = XCTAttachment(screenshot: shot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func note(_ phase: String, card: CGRect, edges: [Double]) {
        let text = String(format: "[held-card-iris] %@ card=%@ ring top %.2f right %.2f bottom %.2f left %.2f",
                          phase, NSCoder.string(for: card), edges[0], edges[1], edges[2], edges[3])
        print(text)
        let a = XCTAttachment(string: text)
        a.lifetime = .keepAlways
        add(a)
    }
}
