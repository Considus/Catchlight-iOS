//
//  TakeAutoCleanupTests.swift
//  CatchlightCoreTests — the auto-cleanup eligibility rule (owner 2026-06-19).
//
//  The whole point of the rule is its SAFETY guarantees, so they're pinned here:
//  notes and in-progress Takes (and the Obie) are never eligible; only a fully-done,
//  note-free Take past its age window is. `now` is injected so age is deterministic.
//

import XCTest
@testable import CatchlightCore

final class TakeAutoCleanupTests: XCTestCase {

    private let day: TimeInterval = 24 * 60 * 60
    private let base = Date(timeIntervalSince1970: 1_000_000)
    /// `now` two days after `base`, so a Take modified at `base` is "older than a day".
    private var twoDaysLater: Date { base.addingTimeInterval(2 * 24 * 60 * 60) }

    private func reminder(done: Bool) -> TimeReminder {
        TimeReminder(scheduledDate: base, notificationIdentifier: "r", isDone: done)
    }

    // MARK: - Eligible

    func testEligible_completedChecklist_noNote_old() {
        let take = Take(modifiedAt: base, blocks: [.checkItem("milk", isComplete: true),
                                                   .checkItem("eggs", isComplete: true)])
        XCTAssertTrue(take.isAutoCleanupEligible(olderThan: day, now: twoDaysLater))
    }

    func testEligible_completedReminder_noNote_old() {
        let take = Take(modifiedAt: base, blocks: [], timeReminder: reminder(done: true))
        XCTAssertTrue(take.isAutoCleanupEligible(olderThan: day, now: twoDaysLater))
    }

    // MARK: - Protected: notes

    func testProtected_completedChecklistWithProseNote() {
        let take = Take(modifiedAt: base, blocks: [.textLine("don't forget the receipt"),
                                                   .checkItem("milk", isComplete: true)])
        XCTAssertFalse(take.isAutoCleanupEligible(olderThan: day, now: twoDaysLater))
    }

    func testProtected_pureNote() {
        let take = Take(modifiedAt: base, blocks: [.textLine("a thought")])
        XCTAssertFalse(take.isAutoCleanupEligible(olderThan: day, now: twoDaysLater))
    }

    func testProtected_checklistWithBlankTextBlock_isStillEligible() {
        // An empty/whitespace text block is NOT a note — it shouldn't shield the Take.
        let take = Take(modifiedAt: base, blocks: [.textLine("   "),
                                                   .checkItem("milk", isComplete: true)])
        XCTAssertTrue(take.isAutoCleanupEligible(olderThan: day, now: twoDaysLater))
    }

    // MARK: - Protected: in progress

    func testProtected_incompleteChecklist() {
        let take = Take(modifiedAt: base, blocks: [.checkItem("milk", isComplete: true),
                                                   .checkItem("eggs", isComplete: false)])
        XCTAssertFalse(take.isAutoCleanupEligible(olderThan: day, now: twoDaysLater))
    }

    func testProtected_completedTask_butUndoneReminder() {
        let take = Take(modifiedAt: base, blocks: [.checkItem("milk", isComplete: true)],
                        timeReminder: reminder(done: false))
        XCTAssertFalse(take.isAutoCleanupEligible(olderThan: day, now: twoDaysLater))
    }

    // MARK: - Protected: the Obie + age window

    func testProtected_obie_evenWhenCompletedAndNoteFree() {
        let take = Take(modifiedAt: base, blocks: [.checkItem("milk", isComplete: true)],
                        isObie: true)
        XCTAssertFalse(take.isAutoCleanupEligible(olderThan: day, now: twoDaysLater))
    }

    func testProtected_withinWindow() {
        // Modified 12h ago, window = 1 day → not yet old enough.
        let recent = base.addingTimeInterval(-12 * 60 * 60)
        let take = Take(modifiedAt: recent, blocks: [.checkItem("milk", isComplete: true)])
        XCTAssertFalse(take.isAutoCleanupEligible(olderThan: day, now: base))
    }
}
