//  Every Take card is as wide as the toolbar, 17pt from each side, and every Iris is centred
//  under Add (owner 2026-11-11: "The Take card needs to exactly match the width of the menu
//  bar"; art director: option a, the Iris inset worked out per width).

import XCTest

final class CardWidthUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func assertCard(_ frame: CGRect, in window: CGRect, _ what: String) {
        XCTAssertEqual(frame.minX, 17, accuracy: 0.5, "\(what): left edge \(frame.minX)pt, not 17")
        XCTAssertEqual(window.width - frame.maxX, 17, accuracy: 0.5,
                       "\(what): right margin \(window.width - frame.maxX)pt, not 17")
    }

    private func assertUnderAdd(_ iris: CGRect, _ addX: CGFloat, _ what: String) {
        XCTAssertEqual(iris.midX, addX, accuracy: 0.5, "\(what): Iris centre \(iris.midX), Add centre \(addX)")
    }

    func testCardsMatchTheToolbar_andEveryIrisSitsUnderAdd() {
        let app = launchAppForUITesting()
        let add = app.buttons["add-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Toolbar did not load")
        let window = app.windows.firstMatch.frame
        let addX = add.frame.midX
        print("[card-width] window \(window) add \(add.frame)")

        // Timeline.
        let row = takeRow(in: app, withLabelStarting: "Buy film")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Seeded Take not on the timeline")
        assertCard(row.frame, in: window, "Timeline card")
        for iris in app.descendants(matching: .any).matching(identifier: "take-iris").allElementsBoundByIndex
        where iris.frame.minY < add.frame.minY {
            assertUnderAdd(iris.frame, addX, "Timeline Iris")
        }

        // Pinned Obie.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).press(forDuration: 1.2)
        let makeObie = app.buttons["Make Obie"]
        XCTAssertTrue(makeObie.waitForExistence(timeout: 5), "Long-press menu did not appear")
        makeObie.tap()
        sleep(1)
        let obieIris = app.descendants(matching: .any).matching(identifier: "take-iris").allElementsBoundByIndex
            .min { $0.frame.minY < $1.frame.minY }!
        assertUnderAdd(obieIris.frame, addX, "Obie Iris")
        let obieCard = takeRow(in: app, withLabelStarting: "Buy film")
        print("[card-width] obie \(obieCard.frame) iris \(obieIris.frame)")
        assertCard(obieCard.frame, in: window, "Obie card")

        // The editor.
        tapUntil(add, appears: app.textViews["take-edit-body"])
        let shape = anyElement(in: app, id: "editor-shape")
        XCTAssertTrue(shape.waitForExistence(timeout: 5), "editor-shape not in the tree")
        print("[card-width] editor iris \(shape.frame)")
        assertUnderAdd(shape.frame, addX, "Editor Iris")
    }
}
