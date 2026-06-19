//
//  TakeRowViewTests.swift
//  CatchlightTests (app module) — Phase 4 checklist progress + completed state
//
//  Covers the timeline row's spoken status wording: the "3 of 5 complete"
//  progress phrasing (2+ items) and the completed-Task phrasing.
//

import XCTest
import CatchlightCore
@testable import Catchlight

final class TakeRowViewTests: XCTestCase {

    func testStatus_multiItemTask_speaksProgress() {
        let take = Take(blocks: [.checkItem("milk", isComplete: true),
                                 .checkItem("eggs"),
                                 .checkItem("bread")])
        XCTAssertEqual(TakeRowView.statusDescription(for: take), "Task, 1 of 3 complete")
    }

    func testStatus_fullyCompleteMultiItemTask_speaksAllDone() {
        let take = Take(blocks: [.checkItem("a", isComplete: true),
                                 .checkItem("b", isComplete: true)])
        XCTAssertTrue(take.isComplete)
        XCTAssertEqual(TakeRowView.statusDescription(for: take), "Task, 2 of 2 complete")
    }

    func testStatus_oneItemTask_speaksProgressWithCount() {
        // A single-item Task now speaks its count too (owner 2026-06-19: single-item
        // tasks show "0 of 1 completed"), matching the visible progress marker — was
        // "Task, complete" / "Task" with no count under the old 2+ progress threshold.
        XCTAssertEqual(TakeRowView.statusDescription(for: Take(blocks: [.checkItem("x", isComplete: true)])),
                       "Task, 1 of 1 complete")
        XCTAssertEqual(TakeRowView.statusDescription(for: Take(blocks: [.checkItem("x")])),
                       "Task, 0 of 1 complete")
    }

    func testStatus_plainNote() {
        XCTAssertEqual(TakeRowView.statusDescription(for: Take(blocks: [.textLine("a thought")])), "Note")
    }

    func testStatus_obie() {
        let take = Take(blocks: [.textLine("the star")], isObie: true)
        let status = TakeRowView.statusDescription(for: take)
        XCTAssertTrue(status.contains("Obie, your pinned Take"))
    }
}
