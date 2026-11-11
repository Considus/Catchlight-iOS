//
//  OnboardingPhraseReachUITests.swift
//  CatchlightUITests
//
//  On the step that asks for three words of the Privacy phrase, every one of the twelve word
//  buttons can be brought to a place where it can be tapped: never left under the bottom
//  buttons, and never dropped from the screen because the grid had no room for it.
//

import XCTest

final class OnboardingPhraseReachUITests: XCTestCase {

    func testEveryPhraseWordCanBeReached_atDefaultSize() {
        checkEveryWordReachable(contentSize: nil)
    }

    func testEveryPhraseWordCanBeReached_atLargestTextSize() {
        checkEveryWordReachable(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    private func checkEveryWordReachable(contentSize: String?) {
        continueAfterFailure = true
        var words = [String]()
        var checked = 0
        walkOnboarding(contentSize: contentSize) { step, app in
            switch step {
            case .reveal:
                for position in 1...12 {
                    let word = app.descendants(matching: .any)
                        .matching(NSPredicate(format: "label BEGINSWITH %@", "Word \(position): ")).firstMatch
                    if contentSize != nil { scrollUntilHittable(word, in: app) }
                    words.append(word.label.replacingOccurrences(of: "Word \(position): ", with: ""))
                }
            case .confirm:
                for word in words {
                    let tile = app.buttons[word]
                    XCTAssertTrue(reach(tile, in: app), "'\(word)' could not be brought to a tappable place: \(tile.frame)")
                    checked += 1
                }
            default:
                break
            }
        }
        XCTAssertEqual(words.count, 12, "the twelve words were not read")
        XCTAssertEqual(checked, 12, "not every word was checked")
    }

    /// The word tiles draw 40 tall but keep the 44pt touch target: the button's frame is 44, the
    /// drawn tile starts 2pt inside it, and a tap between the two still places the word.
    func testWordTilesKeepA44ptTouchTarget() {
        continueAfterFailure = true
        var checked = false
        walkOnboarding { step, app in
            guard step == .confirm, !checked else { return }
            checked = true
            let tiles = app.buttons.allElementsBoundByIndex
                .filter { $0.label.range(of: "^[a-z]+$", options: .regularExpression) != nil && $0.isHittable }
            guard let tile = tiles.min(by: { $0.frame.minY < $1.frame.minY }) else { return XCTFail("no word tile on screen") }
            let frame = tile.frame
            XCTAssertEqual(frame.height, 44, accuracy: 0.5, "the word tile's touch target is not 44 tall")

            // Where the drawn tile starts: the first pixel row down the tile's middle that is not
            // the page colour of the row just above the touch frame.
            let inset = drawnTopInset(of: frame, in: app)
            print("[tap-area] tile \(tile.label) frame=\(NSCoder.string(for: frame)) drawn top inset=\(inset)")
            XCTAssertEqual(inset, 2, accuracy: 0.7, "the tile should draw 2pt inside its 44pt target, so 40 tall")

            // 1pt inside the touch frame, outside the drawn tile: the word is placed.
            let firstSlot = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH 'Word ' AND label CONTAINS 'of your phrase'")).firstMatch
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.midX, dy: frame.minY + 1)).tap()
            Thread.sleep(forTimeInterval: 0.4)
            XCTAssertTrue(firstSlot.label.contains(": \(tile.label)."),
                          "a tap just outside the drawn tile missed it: \(firstSlot.label)")
            // Take the word back out, so the walk can carry on with the right words.
            firstSlot.tap()
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(checked, "the Confirm step was not reached")
    }

    private func drawnTopInset(of frame: CGRect, in app: XCUIApplication) -> CGFloat {
        guard let image = XCUIScreen.main.screenshot().image.cgImage,
              let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return -1 }
        let scale = CGFloat(image.width) / app.frame.width
        let bpp = image.bitsPerPixel / 8
        func rgb(_ y: Int) -> [Int] {
            let p = bytes + y * image.bytesPerRow + Int(frame.midX * scale) * bpp
            return [Int(p[0]), Int(p[1]), Int(p[2])]
        }
        let top = Int((frame.minY * scale).rounded())
        let page = rgb(top - 1)
        var y = top
        while y < top + Int(8 * scale), zip(rgb(y), page).allSatisfy({ abs($0 - $1) <= 10 }) { y += 1 }
        return CGFloat(y - top) / scale
    }

    /// Scrolls in short drags until the element can be tapped. An element the grid has not drawn
    /// yet has no frame, so the drag reveals what lies below first.
    private func reach(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        // Measured on an iPhone SE: XCUITest called a word hittable while it sat under the bottom
        // button, and the tap went to the button. So the word must also clear the button's top.
        let buttonTop = app.buttons["Show my words once more"].frame.minY
        func clear() -> Bool {
            element.exists && element.isHittable && element.frame.minY >= 0 && element.frame.maxY <= buttonTop
        }
        for _ in 0..<30 {
            if clear() { return true }
            let up = !element.exists || element.frame.midY >= app.frame.midY
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.6 : 0.3))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.45 : 0.45))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        return clear()
    }
}
