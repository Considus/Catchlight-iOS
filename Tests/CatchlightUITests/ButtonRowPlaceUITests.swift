//
//  ButtonRowPlaceUITests.swift
//  CatchlightUITests
//
//  The lock screen, Privacy phrase and Cloud Storage put their bottom buttons at the Dailies
//  toolbar's place, half its height, with its side insets and its bottom edge, like onboarding.
//  Phrase entry's bar above the keyboard is checked in `RestoreBarHeightTests`.
//

import XCTest

final class ButtonRowPlaceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// The Dailies toolbar's panel: the Add column's leading edge to the Search column's
    /// trailing edge, at their full height.
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

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"] + extra
        app.launch()
        return app
    }

    private func assertAtToolbarPlace(_ button: XCUIElement, _ toolbar: CGRect, _ screen: String,
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(button.waitForExistence(timeout: 12), "\(screen): button not found", file: file, line: line)
        Thread.sleep(forTimeInterval: 1)   // let a sheet finish rising before reading frames
        let frame = button.frame
        XCTAssertEqual(frame.height, toolbar.height / 2, accuracy: 0.5, "\(screen): height", file: file, line: line)
        XCTAssertEqual(frame.maxY, toolbar.maxY, accuracy: 0.5, "\(screen): bottom edge", file: file, line: line)
        XCTAssertEqual(frame.minX, toolbar.minX, accuracy: 0.5, "\(screen): leading inset", file: file, line: line)
        XCTAssertEqual(frame.maxX, toolbar.maxX, accuracy: 0.5, "\(screen): trailing inset", file: file, line: line)
    }

    func testLockScreenButtonTakesTheToolbarPlace() {
        let toolbar = dailiesToolbarFrame()
        let app = launch(["--uitesting-locked"])
        XCTAssertTrue(app.staticTexts["Catchlight is locked"].waitForExistence(timeout: 12))
        let button = app.buttons.matching(NSPredicate(format: "label IN %@", ["Unlock", "Try again", "Unlocking…"])).firstMatch
        assertAtToolbarPlace(button, toolbar, "lock screen")
    }

    func testPrivacyPhraseRevealButtonTakesTheToolbarPlace() {
        let toolbar = dailiesToolbarFrame()
        let app = launch(["--uitesting-phrase"])
        assertAtToolbarPlace(app.buttons["Reveal phrase"], toolbar, "Privacy phrase, reveal")
    }

    func testPrivacyPhraseHoldButtonTakesTheToolbarPlace() {
        let toolbar = dailiesToolbarFrame()
        let app = launch(["--uitesting-phrase", "--uitesting-phrase-revealed"])
        assertAtToolbarPlace(app.buttons["Hold to reveal phrase"], toolbar, "Privacy phrase, hold")
    }

    func testCloudStorageChooseFolderTakesTheToolbarPlace() {
        let toolbar = dailiesToolbarFrame()
        let app = launch(["--uitesting-cloud-storage"])
        assertAtToolbarPlace(app.buttons["Choose folder from Files"], toolbar, "Cloud Storage")
    }

    /// How far in from the button's leading edge its fill starts, 3pt above its bottom edge. A
    /// shape that follows the screen's curve starts much further in there than the control
    /// radius does, so equal readings mean the same corner.
    private func bottomCornerInset(of button: XCUIElement) -> CGFloat {
        let shot = XCUIScreen.main.screenshot().image
        guard let cg = shot.cgImage, let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return -1 }
        let scale = CGFloat(cg.width) / shot.size.width
        let bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
        func rgb(_ x: Int, _ y: Int) -> [Int] { (0..<3).map { Int(bytes[y * bpr + x * bpp + $0]) } }
        let frame = button.frame
        let y = Int((frame.maxY - 3) * scale)
        let fill = rgb(Int(frame.midX * scale), y)
        var x = Int(frame.minX * scale)
        while x < Int(frame.midX * scale), zip(rgb(x, y), fill).contains(where: { abs($0 - $1) > 24 }) { x += 1 }
        return CGFloat(x) / scale - frame.minX
    }

    func testPrivacyPhraseHoldButtonDrawsTheRevealButtonsShape() {
        var app = launch(["--uitesting-phrase"])
        let reveal = app.buttons["Reveal phrase"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 12))
        Thread.sleep(forTimeInterval: 1)
        let revealInset = bottomCornerInset(of: reveal)
        app.terminate()
        app = launch(["--uitesting-phrase", "--uitesting-phrase-revealed"])
        let hold = app.buttons["Hold to reveal phrase"]
        XCTAssertTrue(hold.waitForExistence(timeout: 12))
        Thread.sleep(forTimeInterval: 1)
        let holdInset = bottomCornerInset(of: hold)
        // The screen-following edge shape needs iOS 26. Below it the edge panel draws the plain
        // surface radius (`flatEdgePanel`), so only the match between the two is checked there.
        if #available(iOS 26, *) {
            XCTAssertGreaterThan(revealInset, 8, "the Reveal button's corner should follow the screen's curve")
        }
        XCTAssertEqual(holdInset, revealInset, accuracy: 1, "the hold button's bottom corner")
    }

    /// With no folder chosen, the sheet's groups spread down the page: the gap from the intro to
    /// the folder card equals the gap from the fine print to the sync card, and neither closes
    /// below 24pt. No empty slot is left where the button was. Each card's text sits 16 inside it.
    func testCloudStorageSpreadsItsGroupsEvenly() {
        let app = launch(["--uitesting-cloud-storage"])
        let intro = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Catchlight never sees'")).firstMatch
        let recommendation = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Easiest'")).firstMatch
        let fine = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Tested with'")).firstMatch
        let sync = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sync'")).firstMatch
        XCTAssertTrue(recommendation.waitForExistence(timeout: 12))
        Thread.sleep(forTimeInterval: 1)
        let aboveFolder = (recommendation.frame.minY - 16) - intro.frame.maxY
        let aboveSync = (sync.frame.minY - 16) - fine.frame.maxY
        XCTAssertGreaterThanOrEqual(aboveFolder, 24, "the folder card is closer than 24 to the intro")
        XCTAssertEqual(aboveFolder, aboveSync, accuracy: 1, "the groups are not spread evenly")
    }
}
