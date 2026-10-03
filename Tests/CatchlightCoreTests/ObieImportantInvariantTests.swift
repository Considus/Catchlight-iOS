//
//  ObieImportantInvariantTests.swift
//  CatchlightCoreTests
//
//  An Obie is always Important (owner decision 2026-10-03, matching the Mac prototype).
//  The card menu's "Remove Important" and the editor bar's Important button both wrote
//  `isImportant = false` onto an Obie; the flag came back only on the next launch, through
//  the decoder. These tests pin the rule on the Take itself, so every write path is
//  covered, not just the ones a menu offers.
//

import XCTest
@testable import CatchlightCore

final class ObieImportantInvariantTests: XCTestCase {

    func testObie_clearingImportant_leavesItImportant() {
        var obie = Take(blocks: [.textLine("the one")], isObie: true)
        obie.isImportant = false
        XCTAssertTrue(obie.isImportant, "An Obie must stay Important when the flag is cleared.")
    }

    /// The exact write the card menu and the editor bar made.
    func testObie_togglingImportant_leavesItImportant() {
        var obie = Take(blocks: [.textLine("the one")], isObie: true)
        obie.isImportant.toggle()
        XCTAssertTrue(obie.isImportant, "Toggling Important on an Obie must not turn it off.")
    }

    /// Control: the guard is Obie-only. A standard Take's Important mark still comes off.
    func testStandardTake_importantCanBeCleared() {
        var take = Take(blocks: [.textLine("ordinary")], isImportant: true)
        take.isImportant.toggle()
        XCTAssertFalse(take.isImportant)
    }

    /// Importance is sticky after demotion (owner 2026-06-18) but no longer locked: once
    /// the Take is not the Obie, its Important mark can be removed like any other.
    func testDemotedObie_importantCanThenBeCleared() {
        var take = Take(blocks: [.textLine("was the one")], isObie: true)
        take.isObie = false
        XCTAssertTrue(take.isImportant, "Demotion leaves Important set (sticky).")
        take.isImportant = false
        XCTAssertFalse(take.isImportant, "A former Obie's Important mark can be removed.")
    }

    /// The menus and the editor bar ask the Take whether its Important mark can change.
    func testCanChangeImportant_falseOnlyForAnObie() {
        XCTAssertFalse(Take(isObie: true).canChangeImportant)
        XCTAssertTrue(Take().canChangeImportant)
        XCTAssertTrue(Take(isImportant: true).canChangeImportant)
    }

    /// Nothing written to the store can be an Obie without Important.
    func testStore_obieWithImportantCleared_readsBackImportant() throws {
        var obie = Take(blocks: [.textLine("the one")], isObie: true)
        obie.isImportant = false
        let store = InMemoryTakeStore()
        try store.upsert(obie)
        let stored = try XCTUnwrap(try store.take(id: obie.id))
        XCTAssertTrue(stored.isObie)
        XCTAssertTrue(stored.isImportant)
    }
}
