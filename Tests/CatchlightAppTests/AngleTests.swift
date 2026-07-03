//
//  AngleTests.swift
//  CatchlightTests (app module) — Phase 3 list Angle (D-033)
//
//  Covers the Angle abstraction's applicability predicate and registry. The
//  Angle type lives in the app target (its presentation is SwiftUI), so this is
//  an `@testable import Catchlight` unit test rather than a CatchlightCore one.
//

import XCTest
import CatchlightCore
@testable import Catchlight

final class AngleTests: XCTestCase {

    // MARK: - The list Angle's predicate

    func testShotList_appliesToTakesWithCheckItems() {
        let task = Take(blocks: [.textLine("Shopping"), .checkItem("milk")])
        XCTAssertTrue(Angle.list.appliesTo(task), "the list Angle applies to a Take with check items")
    }

    func testShotList_doesNotApplyToPlainNote() {
        let note = Take(blocks: [.textLine("just a thought")])
        XCTAssertFalse(Angle.list.appliesTo(note), "no check items ⇒ the list Angle does not apply")

        XCTAssertFalse(Angle.list.appliesTo(Take()), "an empty Take is not a list, either")
    }

    func testShotList_appliesEqualsIsTask() {
        // The predicate is exactly "the Take is a Task" — verify they track.
        let cases = [
            Take(blocks: [.textLine("note")]),
            Take(blocks: [.checkItem("a")]),
            Take(blocks: [.textLine("x"), .checkItem("a", isComplete: true)])
        ]
        for take in cases {
            XCTAssertEqual(Angle.list.appliesTo(take), take.isTask)
        }
    }

    // MARK: - Registry

    func testRegistry_dayOneRegistersOnlyTheShotList() {
        XCTAssertEqual(AngleRegistry.all.map(\.id), ["list"])
    }

    func testRegistry_applicableFiltersByPredicate() {
        let task = Take(blocks: [.checkItem("milk")])
        let note = Take(blocks: [.textLine("thought")])
        XCTAssertEqual(AngleRegistry.applicable(to: task).map(\.id), ["list"],
                       "the affordance shows (one Angle) for a Take with items")
        XCTAssertTrue(AngleRegistry.applicable(to: note).isEmpty,
                      "no affordance for a plain note")
    }

    // MARK: - The Angle path mutates the real Take (tick / reorder)

    func testAnglePath_tickAndReorderMutateTheTake() {
        // The Angle ticks via `toggleItemComplete` and reorders via `blocks.move`
        // / `moveBlock` — the same block mutations an edit uses, so changes persist
        // like any edit. Exercise that path here.
        let a = TakeBlock.checkItem("apples")
        let b = TakeBlock.checkItem("bread")
        var take = Take(blocks: [a, b])

        take.toggleItemComplete(blockID: a.id)
        XCTAssertEqual(take.checkItems.first { $0.id == a.id }?.isComplete, true)
        XCTAssertFalse(take.isComplete, "one ticked of two is not complete")

        take.blocks.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(take.blocks.map(\.id), [b.id, a.id], "reorder persists on the Take")
    }
}
