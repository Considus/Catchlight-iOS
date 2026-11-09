//
//  FocusRowLayoutUITests.swift
//  CatchlightUITests
//
//  Where the open Focus row's marks land on screen: centred exactly on the tapped card's
//  bottom edge once it has grown 22pt, 60pt apart, with no vertical stagger.
//

import XCTest

final class FocusRowLayoutUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private let markIDs = ["note", "task", "remind", "important"].map { "focus-row-mark-\($0)" }

    func testMarksSitOnTheGrownBottomEdge_60Apart() throws {
        let app = launchAppForUITesting()
        let card = takeRow(in: app, withLabelStarting: "Call the framer")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Seeded Take not on the timeline")
        let cardFrame = card.frame
        let iris = anyElement(in: app, id: "take-iris")
        let hub = CGPoint(x: iris.frame.midX, y: iris.frame.midY)
        print("[focus-row-layout] card \(cardFrame) iris \(iris.frame)")

        iris.tap()
        let marks = markIDs.map { anyElement(in: app, id: $0) }
        XCTAssertTrue(marks[0].waitForExistence(timeout: 5), "Focus row did not open")
        sleep(1)
        let frames = marks.map(\.frame)
        print("[focus-row-layout] marks \(frames.map { NSCoder.string(for: $0) })")

        for (i, f) in frames.enumerated() {
            XCTAssertEqual(f.width, 44, accuracy: 0.5, "\(markIDs[i]) is not 44 wide")
            XCTAssertEqual(f.midY, cardFrame.maxY + 22, accuracy: 1,
                           "\(markIDs[i]) is not centred on the card's grown bottom edge")
            XCTAssertEqual(f.midX - hub.x, CGFloat(60 * (i + 1)), accuracy: 1,
                           "\(markIDs[i]) is not \(60 * (i + 1))pt right of the Iris centre")
            XCTAssertEqual(f.midY, frames[0].midY, accuracy: 0.5, "The marks are staggered")
        }
    }
}

/// Every mark and every Iris offers at least a 44pt touch area, and a mark takes a tap near
/// its corners: nothing drawn over it (the dimmed area, the row's Iris) shrinks it. 6pt in,
/// because the very tips of each corner follow the mark's rounded face (radius 10):
/// measured, a tap 3pt in from both edges of a corner, and once 4pt in, fell through to the
/// dimmed area, while 3pt in from one edge alone was taken.
final class FocusRowTouchAreaUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func tap(_ app: XCUIApplication, _ element: XCUIElement, inset dx: CGFloat, _ dy: CGFloat) {
        let f = element.frame
        let x = dx >= 0 ? f.minX + dx : f.maxX + dx
        let y = dy >= 0 ? f.minY + dy : f.maxY + dy
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
    }

    private func assertAtLeast44(_ element: XCUIElement, _ name: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        // 0.01 allows for the frame's floating-point rounding (43.999999999999986).
        XCTAssertGreaterThanOrEqual(element.frame.width, 43.99, "\(name) is under 44pt wide", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 43.99, "\(name) is under 44pt tall", file: file, line: line)
    }

    func testMarks_areAtLeast44_andTakeTapsAtTheirCorners() {
        let app = launchAppForUITesting()
        let iris = anyElement(in: app, id: "take-iris")
        XCTAssertTrue(iris.waitForExistence(timeout: 10), "No Take on the timeline")
        assertAtLeast44(iris, "The timeline Iris")
        iris.tap()
        let mark: (String) -> XCUIElement = { anyElement(in: app, id: "focus-row-mark-\($0)") }
        XCTAssertTrue(mark("task").waitForExistence(timeout: 5), "Focus row did not open")
        sleep(1)
        for kind in ["note", "task", "remind", "important"] { assertAtLeast44(mark(kind), kind) }

        // 6pt in from opposite corners, each tap toggling the mark.
        tap(app, mark("task"), inset: 6, 6)
        XCTAssertEqual(mark("task").value as? String, "active", "Task's top-left corner took no tap")
        tap(app, mark("note"), inset: 6, 6)
        XCTAssertEqual(mark("note").value as? String, "inactive", "Note's top-left corner took no tap")
        tap(app, mark("note"), inset: -6, -6)
        XCTAssertEqual(mark("note").value as? String, "active", "Note's bottom-right corner took no tap")
        tap(app, mark("task"), inset: -6, -6)
        XCTAssertEqual(mark("task").value as? String, "inactive", "Task's bottom-right corner took no tap")
        tap(app, mark("important"), inset: -6, 6)
        XCTAssertEqual(mark("important").value as? String, "active", "Important's top-right corner took no tap")
        tap(app, mark("important"), inset: 6, -6)
        XCTAssertEqual(mark("important").value as? String, "inactive", "Important's bottom-left corner took no tap")
        tap(app, mark("remind"), inset: 6, -6)
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Remind's bottom-left corner took no tap")
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        tap(app, mark("remind"), inset: -6, 6)
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Remind's top-right corner took no tap")
    }

    func testEditorIris_isAtLeast44() {
        let app = launchAppForUITesting()
        let add = app.buttons["add-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Dock did not load")
        tapUntil(add, appears: app.textViews["take-edit-body"])
        let iris = anyElement(in: app, id: "editor-shape")
        XCTAssertTrue(iris.waitForExistence(timeout: 5), "editor-shape not in the tree")
        assertAtLeast44(iris, "The editing card's Iris")
    }

    func testPinnedObieIris_isAtLeast44() {
        let app = launchAppForUITesting()
        let row = takeRow(in: app, withLabelStarting: "Buy film")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Seeded Take not on the timeline")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).press(forDuration: 1.2)
        let makeObie = app.buttons["Make Obie"]
        XCTAssertTrue(makeObie.waitForExistence(timeout: 5), "Long-press menu did not appear")
        makeObie.tap()
        sleep(1)
        let irises = app.descendants(matching: .any).matching(identifier: "take-iris").allElementsBoundByIndex
        XCTAssertFalse(irises.isEmpty, "No Iris on screen")
        let obieIris = irises.min { $0.frame.minY < $1.frame.minY }!
        assertAtLeast44(obieIris, "The pinned Obie's Iris")
    }
}
