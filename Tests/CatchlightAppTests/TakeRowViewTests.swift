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

    // MARK: - V4 (audit 2026-08): overdue / snoozed spoken state

    private func reminderTake(offset: TimeInterval, now: Date,
                              recurrence: TimeReminder.Recurrence = .none) -> Take {
        var take = Take(blocks: [.textLine("call the framer")])
        take.timeReminder = TimeReminder(scheduledDate: now.addingTimeInterval(offset),
                                         notificationIdentifier: take.id.uuidString,
                                         recurrence: recurrence)
        return take
    }

    func testStatus_overdueReminder_speaksOverdue() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let status = TakeRowView.statusDescription(for: reminderTake(offset: -3600, now: now), now: now)
        XCTAssertTrue(status.contains("Overdue"), "got: \(status)")
    }

    func testStatus_snoozedOverdueReminder_speaksSnoozedNotOverdue() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let status = TakeRowView.statusDescription(for: reminderTake(offset: -3600, now: now),
                                                   now: now, isSnoozed: true)
        XCTAssertTrue(status.contains("Snoozed"), "got: \(status)")
        XCTAssertFalse(status.contains("Overdue"), "got: \(status)")
    }

    func testStatus_futureReminder_speaksNeither() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let status = TakeRowView.statusDescription(for: reminderTake(offset: 3600, now: now), now: now)
        XCTAssertFalse(status.contains("Overdue"), "got: \(status)")
        XCTAssertFalse(status.contains("Snoozed"), "got: \(status)")
    }

    // MARK: - Fix 6 (audit 2026-08 §15i): the Obie Iris said "Obie" twice

    private func occurrences(of word: String, in text: String) -> Int {
        text.components(separatedBy: word).count - 1
    }

    func testIrisLabel_obieNote_saysObieExactlyOnce() {
        let take = Take(blocks: [.textLine("the star")], isObie: true)
        let label = TakeRowView.irisAccessibilityLabel(for: take)
        // D-231 (VC2): the Iris is named for its Take, name first.
        XCTAssertEqual(label, "Iris, the star. Obie — your pinned Take. Important, Note", "got: \(label)")
        XCTAssertEqual(occurrences(of: "Obie", in: label), 1, "got: \(label)")
    }

    func testIrisLabel_obieWithNoOtherQuality_speaksImportantNotNote() {
        // The CAUTION case: could dropping the Obie token leave the activity list
        // empty and fall it to the "Note" fallback? No — measured: `isObie`'s
        // didSet forces `isImportant = true` (sticky, by design), so an Obie's
        // list always carries at least "Important". The fallback is structurally
        // unreachable for an Obie; the helper still guards it by returning ""
        // (never a fake "Note") should the model ever decouple the two.
        let take = Take(blocks: [], isNote: false, isObie: true)
        XCTAssertTrue(take.isImportant, "isObie must imply isImportant")
        let label = TakeRowView.irisAccessibilityLabel(for: take)
        XCTAssertEqual(label, "Iris. Obie — your pinned Take. Important", "got: \(label)")
        XCTAssertEqual(occurrences(of: "Obie", in: label), 1)
        XCTAssertFalse(label.contains("Note"), "got: \(label)")
    }

    func testIrisLabel_standardTake_namedForItsTake() {
        // D-231 (VC2): "Iris, <first line>" so Voice Control can address one Iris.
        XCTAssertEqual(TakeRowView.irisAccessibilityLabel(for: Take(blocks: [.textLine("a")])),
                       "Iris, a. Note")
    }

    func testIrisLabel_emptyTake_staysBareIris() {
        XCTAssertEqual(TakeRowView.irisAccessibilityLabel(for: Take(blocks: [.textLine("")])),
                       "Iris. Note")
    }

    func testIrisName_truncatesWordSafeAtLimit() {
        // D-231's length guard: cut word-safe at 40 characters, ellipsis appended.
        let long = "Pick up the developed rolls from the lab on Thursday afternoon"
        let name = TakeRowView.irisNameTruncated(long)
        XCTAssertTrue(name.count <= 41, "got \(name.count): \(name)")
        XCTAssertTrue(name.hasSuffix("…"), "got: \(name)")
        XCTAssertEqual(name, "Pick up the developed rolls from the…", "got: \(name)")
        // Short lines pass through untouched.
        XCTAssertEqual(TakeRowView.irisNameTruncated("Buy film"), "Buy film")
    }

    func testActivityDescription_defaultStillIncludesObie() {
        // Every existing caller (editor footer included) uses the default and
        // must not change.
        let take = Take(blocks: [.textLine("the star")], isObie: true)
        XCTAssertEqual(TakeCircleView.activityDescription(for: take), "Obie, Important, Note")
    }

    func testIrisHint_namesTheRotorRoute_neverTheGesture() {
        let obie = Take(blocks: [.textLine("x")], isObie: true)
        let standard = Take(blocks: [.textLine("x")])
        XCTAssertEqual(TakeRowView.irisAccessibilityHint(for: standard),
                       "Opens the Focus ring. Use the actions rotor to make this your Obie.")
        XCTAssertEqual(TakeRowView.irisAccessibilityHint(for: obie),
                       "Opens the Focus ring. Use the actions rotor to turn this back into a standard Take.")
        XCTAssertFalse(TakeRowView.irisAccessibilityHint(for: obie).contains("Long press"))
        XCTAssertFalse(TakeRowView.irisAccessibilityHint(for: standard).contains("Long press"))
    }

    // MARK: - VC1 (audit 2026-08, D-217): a link Take must be addressable by voice

    func testLabel_noLink_byteIdenticalToToday() {
        // The case that must not move: a linkless Take announces exactly as before.
        XCTAssertEqual(TakeRowView.accessibilityLabel(for: Take(blocks: [.textLine("Call the framer back")])),
                       "Call the framer back. Note")
    }

    func testLabel_textAndLink_speaksWordsThenDomain() {
        let take = Take(blocks: [.textLine("Watch this later https://www.youtube.com/watch?v=oKd6dpJspQ")])
        XCTAssertEqual(TakeRowView.accessibilityLabel(for: take),
                       "Watch this later. Link to youtube.com. Note")
    }

    func testLabel_linkOnly_speaksDomainAlone() {
        let take = Take(blocks: [.textLine("https://www.youtube.com/watch?v=oKd6dpJspQ")])
        XCTAssertEqual(TakeRowView.accessibilityLabel(for: take),
                       "Link to youtube.com. Note")
    }

    func testLabel_linkTake_containsNoUrlPunctuation() {
        // ":", "/" and "?" are what Voice Control mangles into an unsayable name.
        for text in ["Watch this later https://www.youtube.com/watch?v=oKd6dpJspQ",
                     "https://www.photobox.co.uk/prints"] {
            let label = TakeRowView.accessibilityLabel(for: Take(blocks: [.textLine(text)]))
            XCTAssertFalse(label.contains(":"), "got: \(label)")
            XCTAssertFalse(label.contains("/"), "got: \(label)")
            XCTAssertFalse(label.contains("?"), "got: \(label)")
        }
    }

    func testLabel_twoLinks_speaksFirstDomainAndCount() {
        // The multi-link wording is claude-4e's default, flagged changeable —
        // the owner settles the phrasing (fix-8 step 4).
        let take = Take(blocks: [.textLine("compare https://a.com/x and https://b.org/y")])
        XCTAssertEqual(TakeRowView.accessibilityLabel(for: take),
                       "compare and. Link to a.com and 1 more link. Note")
    }

    // MARK: - VC4 (audit 2026-08, D-227): an email speaks as "Email to bob at example.com"

    func testLabel_email_speaksAtNotSymbol() {
        // The spoken "at" survives Voice Control's punctuation stripping; the raw
        // address does not. Same shape as the link rule: the user's words first,
        // then the phrase. (Supersedes the fix-8 "unchanged as today" pin — the
        // behaviour was deliberately left then, and decided now.)
        let label = TakeRowView.accessibilityLabel(for: Take(blocks: [.textLine("Email bob@example.com")]))
        XCTAssertEqual(label, "Email. Email to bob at example.com. Note")
        XCTAssertFalse(label.contains("@"), "got: \(label)")
    }

    func testLabel_emailOnly_speaksPhraseAlone() {
        XCTAssertEqual(TakeRowView.accessibilityLabel(for: Take(blocks: [.textLine("bob@example.com")])),
                       "Email to bob at example.com. Note")
    }

    func testLabel_linkAndEmail_linkPhraseThenEmailPhrase() {
        let take = Take(blocks: [.textLine("send https://a.com/x to bob@example.com")])
        XCTAssertEqual(TakeRowView.accessibilityLabel(for: take),
                       "send to. Link to a.com. Email to bob at example.com. Note")
    }

    func testLabel_twoEmails_collapseLikeLinks() {
        // The same shape as the link rule's multi collapse (D-227 "same shape");
        // the exact multi-email wording is the owner's to overrule.
        let take = Take(blocks: [.textLine("ask bob@example.com or sue@example.org")])
        XCTAssertEqual(TakeRowView.accessibilityLabel(for: take),
                       "ask or. Email to bob at example.com and 1 more email. Note")
    }

    func testStatus_repeatingReminderWithPastAnchor_isNeverOverdue() {
        // A repeating reminder's anchor sits in the past by design yet it always
        // has a next occurrence — isOverdue(now:) returns false when repeats is
        // true, so the row must not speak "Overdue".
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let status = TakeRowView.statusDescription(
            for: reminderTake(offset: -3600, now: now, recurrence: .daily), now: now)
        XCTAssertFalse(status.contains("Overdue"), "got: \(status)")
    }
}
