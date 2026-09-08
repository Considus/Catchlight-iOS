//
//  DockHierarchyProbeTests.swift
//  CatchlightUITests
//
//  V40, remaining half. `DockOrderProbeTests` flattens the tree with
//  `descendants(matching: .any)`, which cannot see CONTAINER STRUCTURE — and
//  containers are the open question. V30 orders the dock with
//  `.accessibilitySortPriority(-1)`, and a sort priority only orders SIBLINGS.
//  If mounting the Add hint moves the dock's buttons into a different container
//  from the one that priority sits on, the priority stops applying to them and
//  each button can become the end of its own run, which is what the owner's log
//  shows: every forward move out of a dock element lands on the first timeline
//  cell.
//
//  `debugDescription` prints the hierarchy with nesting, so it CAN see this.
//
//  ===== WHAT IT MEASURED, 2026-09-08 =====
//
//  1. The container hypothesis is REFUTED. With the hint mounted and without it,
//     the hierarchy is structurally identical: same parent, same nesting, same
//     sibling list. Mounting the hint adds one element and moves nothing. It does
//     not put the buttons in a different container, so that is not why sort
//     priority would stop applying to them.
//
//  2. The dock's four buttons are LOOSE SIBLINGS of the timeline collection and
//     the heading — they have no container of their own:
//
//         Other  (flattened container)
//           CollectionView          <- timeline, nested
//           StaticText 'Dailies'
//           Button add-button
//           Button angle-tab
//           Button sequence-tab
//           Button search-tab
//           StaticText "What's your first Take?"   <- step 1 only
//           Other (empty, 0x0)
//
//     V30's `.accessibilitySortPriority(-1)` therefore has very little structure
//     to hold: it ranks siblings in a flat list rather than moving a group.
//
//  3. The hint's ONE structural effect, before PR #241, was to insert a CONTAINER
//     into that flat run:
//
//         pre-#241:  Other "What's your first Take?"      <- container
//                      StaticText "What's your first Take?"
//         post-#241: StaticText "What's your first Take?" <- flat sibling
//
//     Measured by reverting only the `.combine` line and re-running this probe.
//     So #241 removed the only structural difference the hint introduced. If the
//     dock's wrap-to-first-timeline-cell is structural, #241 addressed it; if it
//     survives, it is not structural and the search moves elsewhere. That is the
//     falsifiable claim the next device pass tests.
//
//  This test asserts nothing; it exists to be read, and re-read against a change.
//  `DockOrderProbeTests` carries the assertion that the hint vends once.
//

import XCTest

final class DockHierarchyProbeTests: XCTestCase {

    private func dumpHierarchy(step: String, title: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-orientation-step", step]
        app.launch()
        XCTAssertTrue(app.buttons["add-button"].firstMatch.waitForExistence(timeout: 20),
                      "Dock did not load at step \(step)")
        print("======== \(title) ========")
        print(app.debugDescription)
        print("======== end \(title) ========")
        app.terminate()
    }

    func testHierarchyWithAndWithoutTheAddHint() {
        dumpHierarchy(step: "1", title: "STEP 1 — Add hint mounted")
        dumpHierarchy(step: "5", title: "STEP 5 — tour complete, no hint")
    }
}
