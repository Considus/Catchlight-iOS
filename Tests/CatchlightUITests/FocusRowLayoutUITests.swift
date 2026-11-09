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
