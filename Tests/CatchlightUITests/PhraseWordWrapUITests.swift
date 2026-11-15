//
//  PhraseWordWrapUITests.swift
//  CatchlightUITests
//
//  No word on the Settings Privacy phrase sheet may break across two lines. The grid of the
//  twelve widest list words must stand exactly as tall as the grid of twelve short ones: a
//  word that wraps makes its row taller.
//

import XCTest

final class PhraseWordWrapUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func gridHeight(_ extra: [String]) -> CGFloat {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-phrase", "--uitesting-phrase-revealed"] + extra
        app.launch()
        let grid = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Phrase '")).firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 10), "the phrase grid did not appear")
        let height = grid.frame.height
        app.terminate()
        return height
    }

    func testTheWidestWordsStayOnOneLine() {
        let short = gridHeight([])
        let wide = gridHeight(["--uitesting-phrase-wide"])
        XCTAssertGreaterThan(short, 100, "expected four rows of words")
        XCTAssertEqual(wide, short, accuracy: 0.5, "a wide word wrapped: the grid grew taller")
    }
}
