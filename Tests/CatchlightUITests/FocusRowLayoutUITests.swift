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

    func testMarksSitOnTheGrownBottomEdge_60Apart_centred() throws {
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
            // 60 apart, as a group centred on the screen (owner 2026-11-12).
            let expected = app.windows.firstMatch.frame.midX + (CGFloat(i) - 1.5) * 60
            XCTAssertEqual(f.midX, expected, accuracy: 1,
                           "\(markIDs[i]) is not at \(expected), its place in a centred row")
            XCTAssertGreaterThan(f.midX, hub.x, "\(markIDs[i]) is left of the Iris")
            XCTAssertEqual(f.midY, frames[0].midY, accuracy: 0.5, "The marks are staggered")
        }
    }

    /// On the lowest Take that sits fully above the toolbar, the marks still drop to just below
    /// the card, over the dimmed toolbar, as they do everywhere else (owner 2026-11-10). Before,
    /// they were held above the toolbar and landed on the card's first line of text.
    func testNearTheToolbar_marksStillDropBelowTheCard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-fill"]
        app.launch()
        let add = app.buttons["add-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Toolbar not shown")
        // The panel's top edge: the Add button sits inside it, so its top is a little lower.
        let toolbarTop = add.frame.minY

        // The lowest Take whose Iris is clear above the toolbar while its marks, dropped below
        // the card, would cross the toolbar's top and still stay clear of the home bar.
        let homeBarTop = app.frame.maxY - 34
        let rows = app.descendants(matching: .any).matching(identifier: "take-row")
        func nearTake() -> CGRect? {
            var card: CGRect?
            for i in 0..<rows.count {
                let f = rows.element(boundBy: i).frame
                let irisBottom = f.minY + 36 + 22
                if f.minY > 120, irisBottom < toolbarTop, f.maxY + 44 > toolbarTop,
                   f.maxY + 44 <= homeBarTop, f.maxY > (card?.maxY ?? 0) { card = f }
            }
            return card
        }
        // Where the list rests depends on the phone's height, so nudge it up a little at a
        // time until a Take sits in that spot.
        sleep(1)
        var card = nearTake()
        for _ in 0..<8 where card == nil {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -25)),
                        withVelocity: .slow, thenHoldForDuration: 0.5)
            card = nearTake()
        }
        let cardFrame = try XCTUnwrap(card, "No Take has its Iris just above the toolbar")
        let irises = app.descendants(matching: .any).matching(identifier: "take-iris")
        var iris: XCUIElement?
        for i in 0..<irises.count where cardFrame.contains(irises.element(boundBy: i).frame.center) {
            iris = irises.element(boundBy: i)
        }
        let hub = try XCTUnwrap(iris, "No Iris inside the chosen Take")
        print("[focus-row-near-toolbar] toolbarTop \(toolbarTop) card \(cardFrame) iris \(hub.frame)")

        hub.tap()
        let mark = anyElement(in: app, id: markIDs[0])
        XCTAssertTrue(mark.waitForExistence(timeout: 5), "Focus row did not open")
        sleep(1)
        print("[focus-row-near-toolbar] mark \(mark.frame)")
        XCTAssertEqual(mark.frame.midY, cardFrame.maxY + 22, accuracy: 1,
                       "Near the toolbar the marks are not centred on the card's grown bottom edge")
    }

    /// The fade behind the toolbar starts `fadeAbove` (16pt) above the panel. A Take whose Iris
    /// sits in that strip still shows through it, so a tap on the Iris must still open its
    /// Focus row: the fade is only a look and must not take touches.
    func testIrisInTheFadeAboveTheToolbar_stillOpensTheFocusRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-fill"]
        app.launch()
        let add = app.buttons["add-button"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Toolbar not shown")
        // The Add button fills the panel's height, so its top is the panel's top.
        let panelTop = add.frame.minY
        let tapY = panelTop - 8      // halfway up the 16pt fade
        let irises = app.descendants(matching: .any).matching(identifier: "take-iris")
        func irisAcrossTheFade() -> XCUIElement? {
            for i in 0..<irises.count {
                let f = irises.element(boundBy: i).frame
                if f.minY + 6 < tapY, tapY < f.maxY - 6 { return irises.element(boundBy: i) }
            }
            return nil
        }
        sleep(1)
        var iris = irisAcrossTheFade()
        // Aim an Iris's centre at the tap line. A drag scrolls the list by less than
        // its length, by the scroll gesture's starting slop, which differs between iOS versions:
        // a fixed small nudge scrolled 5pt a time on iOS 27 and, on CI's iOS 18.5, never got
        // there. So each drag adds the slop, and the slop grows when a drag moves nothing.
        var slop: CGFloat = 10
        for attempt in 0..<10 where iris == nil {
            let before = (0..<irises.count).map { irises.element(boundBy: $0).frame.midY }
            // The list rests at its top and can't move down, so aim the nearest Iris BELOW the
            // line and move the list up.
            guard let nearest = before.filter({ $0 > tapY }).min() else { break }
            let drag = nearest - tapY + slop
            print("[iris-in-fade] try \(attempt): tapY \(tapY) nearest Iris centre \(nearest) drag \(drag)")
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -drag)),
                        withVelocity: .slow, thenHoldForDuration: 0.5)
            let after = (0..<irises.count).map { irises.element(boundBy: $0).frame.midY }
            if Set(before.map { Int($0) }) == Set(after.map { Int($0) }) { slop += 10 }
            iris = irisAcrossTheFade()
        }
        let hub = try XCTUnwrap(iris, "No Iris lies across the fade above the toolbar")
        print("[iris-in-fade] panelTop \(panelTop) tapY \(tapY) iris \(hub.frame)")
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: hub.frame.midX, dy: tapY)).tap()
        XCTAssertTrue(anyElement(in: app, id: markIDs[0]).waitForExistence(timeout: 5),
                      "A tap on an Iris in the fade above the toolbar did not open its Focus row")
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
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
