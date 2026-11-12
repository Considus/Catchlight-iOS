//
//  OnboardingConsistencyUITests.swift
//  CatchlightUITests
//
//  Every onboarding step reads and sits alike: one label for Back, and the bottom buttons in the
//  Dailies toolbar's place, with its height, its side insets and its bottom edge.
//

import XCTest

final class OnboardingConsistencyUITests: XCTestCase {

    /// The primary button of each step that has one. Storage has none: its two cards are the choice.
    private static let primaryLabels: [OnboardingStep: String] = [
        .welcome: "Create my Privacy phrase",
        .restore: "Restore",
        .localWarning: "I know the risk",
        .reveal: "I've written them down",
        .confirm: "Show my words once more",
        .basics: "Next",
        .basicsMore: "Got it",
        .complete: "Start using Catchlight",
    ]

    /// The Dailies toolbar's panel: the four columns, as the Add column's leading edge to the
    /// Search column's trailing edge, at their full height.
    private func dailiesToolbarFrame() -> CGRect {
        let app = launchAppForUITesting()
        let add = anyElement(in: app, id: "add-button")
        let search = anyElement(in: app, id: "search-tab")
        XCTAssertTrue(add.waitForExistence(timeout: 12), "the Dailies toolbar did not appear")
        XCTAssertTrue(search.exists)
        let frame = CGRect(x: add.frame.minX, y: add.frame.minY,
                           width: search.frame.maxX - add.frame.minX, height: add.frame.height)
        app.terminate()
        return frame
    }

    func testNoStepShowsGoBack_andTheBackButtonsSayBack() {
        continueAfterFailure = true
        var backSeen = [OnboardingStep]()
        walkOnboarding { step, app in
            XCTAssertFalse(app.buttons["Go back"].exists, "\(step): a button still says Go back")
            if app.buttons["Back"].exists { backSeen.append(step) }
        }
        XCTAssertEqual(backSeen, [.restore, .localWarning], "the steps with a Back button")
    }

    func testPrimaryButtonsShareOnePlace() {
        continueAfterFailure = true
        var minYs = [OnboardingStep: CGFloat]()
        walkOnboarding { step, app in
            guard let label = Self.primaryLabels[step] else { return }
            let button = app.buttons[label]
            XCTAssertTrue(button.exists, "\(step): no '\(label)' button")
            minYs[step] = button.frame.minY
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "\(step): under the 44pt touch target")
        }
        XCTAssertEqual(minYs.count, Self.primaryLabels.count)
        guard let first = minYs.values.first else { return }
        for (step, y) in minYs {
            XCTAssertEqual(y, first, accuracy: 0.5, "\(step): the primary button's top edge differs from the others")
        }
    }

    func testPrimaryButtonsTakeHalfTheDailiesToolbarHeightAtItsPlace() {
        continueAfterFailure = true
        let toolbar = dailiesToolbarFrame()
        walkOnboarding { step, app in
            guard let label = Self.primaryLabels[step] else { return }
            let frame = app.buttons[label].frame
            XCTAssertEqual(frame.height, toolbar.height / 2, accuracy: 0.5, "\(step): height")
            XCTAssertEqual(frame.maxY, toolbar.maxY, accuracy: 0.5, "\(step): bottom edge")
            XCTAssertEqual(frame.minX, toolbar.minX, accuracy: 0.5, "\(step): leading inset")
            switch step {
            case .restore, .localWarning:
                let back = app.buttons["Back"].frame
                XCTAssertEqual(back.maxX, toolbar.maxX, accuracy: 0.5, "\(step): trailing inset of the pair")
                XCTAssertEqual(back.height, toolbar.height / 2, accuracy: 0.5, "\(step): Back height")
                XCTAssertEqual(back.minY, frame.minY, accuracy: 0.5, "\(step): the pair shares a top edge")
            default:
                XCTAssertEqual(frame.maxX, toolbar.maxX, accuracy: 0.5, "\(step): trailing inset")
            }
        }
    }

    // MARK: - The point cards read as Take cards

    private struct CardLook {
        var frame: CGRect
        var fill: [Int]
        var border: [Int]
        /// How far in from the card's left edge the card first shows at one pixel below its top edge.
        var cornerInset: Int
    }

    /// Reads a card's look off the screen: the colour of its inside near the bottom corner, the
    /// colour of its edge, and how far the top edge's corner rounds away.
    private func look(of frame: CGRect, in app: XCUIApplication) -> CardLook? {
        guard let image = XCUIScreen.main.screenshot().image.cgImage,
              let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let scale = CGFloat(image.width) / app.frame.width
        let bpp = image.bitsPerPixel / 8
        func rgb(_ x: Int, _ y: Int) -> [Int] {
            let p = bytes + y * image.bytesPerRow + x * bpp
            return [Int(p[0]), Int(p[1]), Int(p[2])]
        }
        func far(_ a: [Int], _ b: [Int]) -> Bool { zip(a, b).contains { abs($0 - $1) > 10 } }
        let left = Int(frame.minX * scale), top = Int(frame.minY * scale)
        let fill = rgb(Int((frame.maxX - 6) * scale), Int((frame.maxY - 6) * scale))
        let page = rgb(left - Int(6 * scale), top + Int(frame.height * scale / 2))
        // How far in from the left the card starts on one pixel row. The page shows all the
        // way across on a row above the card.
        func insetOnRow(_ y: Int) -> Int {
            var inset = 0
            while inset < Int(40 * scale), !far(rgb(left + inset, y), page) { inset += 1 }
            return inset
        }
        // Read the corner one row below the card's first drawn row, not one row below its
        // frame. A frame on a third of a point can start a pixel above the drawing, and a 14pt
        // corner moves about 7px per row there, so a row read off the frame compared the
        // corners at different heights. Measured: from their first drawn rows the Take card
        // and a point card read 38, 31, 27, 25, 22 alike, while the frame row read 31 and 38.
        var firstRow = top
        while firstRow < top + Int(4 * scale), insetOnRow(firstRow) >= Int(40 * scale) { firstRow += 1 }
        let inset = insetOnRow(firstRow + 1)
        // The border from the same drawn row: on an iPhone 16 a point card drew 2px below its frame,
        // so the frame's row 1 was still the page.
        let border = rgb(Int(frame.midX * scale), firstRow + 1)
        return CardLook(frame: frame, fill: fill, border: border, cornerInset: inset)
    }

    func testPointCardsLookLikeTakeCards() {
        continueAfterFailure = true
        for mode in ["night", "daylight"] {
            let dailies = XCUIApplication()
            dailies.launchArguments = ["--uitesting", "-appearanceMode", mode]
            dailies.launch()
            let take = dailies.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS 'Buy film'")).firstMatch
            XCTAssertTrue(take.waitForExistence(timeout: 12), "no Take card in Dailies")
            Thread.sleep(forTimeInterval: 0.6)
            guard let takeLook = look(of: take.frame, in: dailies) else { return XCTFail("no screenshot") }
            dailies.terminate()

            walkOnboarding(appearance: mode) { step, app in
                guard step == .basics else { return }
                let card = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label BEGINSWITH 'Shape your Take with the Iris'")).firstMatch
                guard let pointLook = look(of: card.frame, in: app) else { return XCTFail("no screenshot") }
                XCTAssertEqual(pointLook.frame.minX, takeLook.frame.minX, accuracy: 0.5, "\(mode): side margin")
                XCTAssertEqual(pointLook.frame.width, takeLook.frame.width, accuracy: 0.5, "\(mode): width")
                XCTAssertEqual(pointLook.fill.count, 3)
                for i in 0..<3 {
                    XCTAssertEqual(pointLook.fill[i], takeLook.fill[i], accuracy: 10, "\(mode): fill channel \(i)")
                    XCTAssertEqual(pointLook.border[i], takeLook.border[i], accuracy: 24, "\(mode): border channel \(i)")
                }
                XCTAssertEqual(pointLook.cornerInset, takeLook.cornerInset, accuracy: 2, "\(mode): corner")
            }
        }
    }
}
