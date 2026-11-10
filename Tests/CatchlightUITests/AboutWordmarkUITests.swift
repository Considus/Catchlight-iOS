//
//  AboutWordmarkUITests.swift
//  CatchlightUITests
//
//  The About screen's wordmark is one accessibility element named "Catchlight": the
//  letters and the dot of the i read once.
//

import XCTest

final class AboutWordmarkUITests: XCTestCase {

    func testAboutWordmark_isOneElementLabelledCatchlight() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-appearanceMode", "daylight"]
        app.launch()
        let tab = anyElement(in: app, id: "angle-tab")
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.swipeUp()
        XCTAssertTrue(anyElement(in: app, id: "settings-sheet").waitForExistence(timeout: 5))
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "About")).firstMatch
        var scrolls = 0
        while !(row.exists && row.isHittable) && scrolls < 10 { app.swipeUp(); scrolls += 1 }
        row.tap()
        let wordmark = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Catchlight"))
        XCTAssertTrue(wordmark.firstMatch.waitForExistence(timeout: 5), "No Catchlight element on About")
        XCTAssertEqual(wordmark.count, 1, "The wordmark should read once, found \(wordmark.count): \(wordmark.allElementsBoundByIndex.map { $0.elementType.rawValue })")
    }
}
