//
//  HintClaimsCursorTests.swift
//  CatchlightUITests
//
//  🚨 THE REGRESSION THIS EXISTS FOR. Moving the cursor claim from the tooltip's
//  `onAppear` to the parent's `onChange` silently stopped it firing at all: a
//  launch armed at a step has nothing to CHANGE, because the step is set before
//  the view exists. The owner's captures carried no `FOCUS CLAIM` line whatsoever,
//  and nothing on the bench noticed — the hint still appeared, still had the right
//  words, still passed every other test.
//
//  `takeFocus` guards on VoiceOver actually running, so under XCUITest the claim is
//  SKIPPED rather than applied. That is fine for this purpose: the log still records
//  that the code path was REACHED, and "was it reached" is precisely what broke.
//
//  This cannot tell whether the cursor really moves — nothing on the bench can.
//  It tells us the app still tries.
//

import XCTest

final class HintClaimsCursorTests: XCTestCase {

    func testTheAddHintAsksForTheCursorWhenItAppears() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", "1", "--a11y-diag"]
        app.launch()
        XCTAssertTrue(app.buttons["add-button"].firstMatch.waitForExistence(timeout: 20),
                      "Dock did not load")
        XCTAssertTrue(app.descendants(matching: .any)
                        .matching(NSPredicate(format: "label CONTAINS %@", "Double-tap Add Take"))
                        .firstMatch.waitForExistence(timeout: 10),
                      "The hint never appeared, so the claim cannot be judged")
        Thread.sleep(forTimeInterval: 3)   // past VoiceOverFocus's settle delay

        // 🚨 ONLY THIS RUN'S LINES. The diagnostics log is CUMULATIVE across launches, so
        // reading the whole file finds a claim from a PREVIOUS run and passes whatever the
        // current build does. The first version of this test did exactly that: it passed
        // with the fix removed, proving nothing. Cut at the last launch marker.
        let all = try Self.diagnosticsMessages()
        guard let launch = all.lastIndex(where: { $0.hasPrefix("Launch —") }) else {
            return XCTFail("No launch marker in the log, so this run cannot be isolated")
        }
        let log = Array(all[launch...])
        let claims = log.filter { $0.contains("FOCUS CLAIM") && $0.contains("addHint") }
        XCTAssertFalse(claims.isEmpty,
                       "No focus claim was made for the Add hint. The trigger did not fire — "
                       + "the hint appeared and nothing asked for the cursor. Log tail:\n"
                       + log.suffix(12).joined(separator: "\n"))
    }

    /// Read the app's own diagnostics out of its container.
    private static func diagnosticsMessages() throws -> [String] {
        let sim = ProcessInfo.processInfo.environment["SIMULATOR_SHARED_RESOURCES_DIRECTORY"]
        let root = sim.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let candidates = FileManager.default
            .enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.lastPathComponent == "catchlight-diagnostics.json" } ?? []
        guard let url = candidates.first,
              let data = try? Data(contentsOf: url),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw XCTSkip("Diagnostics log not reachable from the test process")
        }
        return rows.compactMap { $0["message"] as? String }
    }
}
