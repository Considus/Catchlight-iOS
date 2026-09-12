//
//  HintElementLifetimeTests.swift
//  CatchlightUITests
//
//  The hint's accessibility ELEMENT dies about a second after it gains focus, and
//  VoiceOver then falls back to the first element on the screen. Measured on the
//  owner's device twice, with the pulse removed, the announcement removed and the
//  unlock re-anchor skipped — so none of those is the cause:
//
//      :36  FOCUS none -> "Double-tap Add Take to write your first Take."
//      :37  FOCUS "Double-tap..." -> none
//      :38  FOCUS none -> "Dailies"
//
//  🚨 The VIEW is not being remounted — `onAppear`/`onDisappear` were instrumented
//  and show one appear and no disappear across the whole window. So it is the
//  accessibility node being replaced under the cursor, not the SwiftUI view.
//
//  That distinction is why this test exists. XCUITest IS an accessibility client,
//  so the tree is materialised here even though no cursor moves — which means the
//  ELEMENT's lifetime is observable on the bench even when focus is not.
//

import XCTest

final class HintElementLifetimeTests: XCTestCase {

    /// Poll the hint for several seconds and record every transition between
    /// present and absent. A stable element gives one run; an element being
    /// replaced gives gaps.
    func testHintElementSurvivesAfterItAppears() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", "1", "--a11y-diag"]
        app.launch()
        XCTAssertTrue(app.buttons["add-button"].firstMatch.waitForExistence(timeout: 20),
                      "Dock did not load")

        let hint = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Double-tap Add Take"))
        XCTAssertTrue(hint.firstMatch.waitForExistence(timeout: 10), "The hint never appeared")

        var samples: [(Date, Bool)] = []
        let start = Date()
        while Date().timeIntervalSince(start) < 8 {
            samples.append((Date(), hint.firstMatch.exists))
        }

        var flips = 0
        for i in 1..<samples.count where samples[i].1 != samples[i - 1].1 {
            flips += 1
            let t = samples[i].0.timeIntervalSince(start)
            print(String(format: "HINT %@ at +%.2fs", samples[i].1 ? "APPEARED" : "VANISHED", t))
        }
        print("HINT samples=\(samples.count) flips=\(flips) present_at_end=\(samples.last?.1 ?? false)")

        XCTAssertEqual(flips, 0,
                       "The hint's accessibility element changed state \(flips) time(s) while "
                       + "it should simply have been present — it is being replaced under the "
                       + "cursor, which is what kills the speech on device.")
    }
}
