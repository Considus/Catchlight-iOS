//
//  Take+AutoCleanup.swift
//  CatchlightCore — opt-in automatic cleanup of finished, note-free Takes
//  (owner 2026-06-19).
//
//  The user — never the app — decides retention ([[catchlight-user-decides-principle]]):
//  Settings offers Never (default) / Daily / Weekly / Monthly / Annually, and the
//  chosen window is an AGE/GRACE threshold. A Take is only EVER a cleanup candidate
//  when it is fully finished AND carries no note, so:
//    • anything still in progress (an unticked task / undone reminder) is safe, and
//    • any Take with prose the user wrote (a "note") is safe — forever.
//  The Obie is never touched (it is the pinned anchor, not an ordinary list Take).
//
//  This is the PURE rule, isolated here so the guarantees are unit-tested without a
//  store or a clock (`now` is injected). The sweep itself (DailiesViewModel) just
//  applies this predicate and deletes the matches on app open.
//

import Foundation

public extension Take {
    /// True when the Take carries a NOTE — any prose (TEXT block) the user wrote.
    /// Checklist item text does NOT count (a ticked shopping list is not "a note"),
    /// which is why this can't lean on `plainText` (that joins every block's text).
    var hasNoteContent: Bool {
        blocks.contains { !$0.isCheck && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Whether this Take is eligible for automatic cleanup under a given age window.
    /// Eligible ⇔ NOT the Obie, fully done (`isMarkedDone` — it has task(s)/reminder(s)
    /// and every one is complete), carries no note, and has been untouched for longer
    /// than `maxAge`. Editing a Take bumps `modifiedAt`, so reopening one resets its
    /// clock and keeps it. `now` is injected for testability.
    func isAutoCleanupEligible(olderThan maxAge: TimeInterval, now: Date) -> Bool {
        guard !isObie else { return false }
        guard isMarkedDone else { return false }
        guard !hasNoteContent else { return false }
        return now.timeIntervalSince(modifiedAt) > maxAge
    }
}
