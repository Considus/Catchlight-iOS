//
//  SeedTakes.swift
//  CatchlightCore
//
//  The five system-authored seed Takes shown on first launch (UX Session Decisions
//  §12). They teach the ring/quadrant system by example and are deleted by the user
//  with the same swipe/edit interaction they will use forever. They are standard
//  Takes in every respect — fully editable and deletable — distinguished only by
//  `isSeeded`, which is cleared on first edit or swipe-delete.
//
//  This is data (model-level), not UI, so it lives in the portable core and is
//  testable. The actual onboarding presentation is Phase 6.
//

import Foundation

public enum SeedTakes {
    /// Build the five seed Takes in display order. `now` anchors their timestamps so
    /// they appear in chronological order beneath the user's first blank Take.
    public static func make(now: Date = Date()) -> [Take] {
        // Anchor to millisecond precision (the canonical wire format) so seed Takes
        // serialise bit-exactly. Offsets are whole seconds, keeping the .000 ms.
        let anchored = ISO8601.date(from: ISO8601.string(from: now)) ?? now
        func at(_ offset: TimeInterval) -> Date { anchored.addingTimeInterval(offset) }

        // 1 — Note (NW active by default).
        var note = Take(createdAt: at(-50), modifiedAt: at(-50),
                        bodyText: "A Take starts as a Note. A thought — nothing more required.",
                        isSeeded: true)

        // 2 — Task (NE).
        var task = Take(createdAt: at(-40), modifiedAt: at(-40),
                        bodyText: "Make it a Task. Something to act on, not just think about.",
                        isTask: true, isSeeded: true)

        // 3 — Reminder (SW). A representative future reminder time.
        var reminder = Take(createdAt: at(-30), modifiedAt: at(-30),
                            bodyText: "Or a Reminder — so it finds you when the moment is right.",
                            isSeeded: true)
        reminder.timeReminder = TimeReminder(
            scheduledDate: at(60 * 60 * 24),   // ~tomorrow; user can change or clear
            notificationIdentifier: reminder.id.uuidString
        )

        // 4 — Obie (SE, glow). The single north-star Take.
        var obie = Take(createdAt: at(-20), modifiedAt: at(-20),
                        bodyText: "Obie is your north star Take. It always leads.",
                        isObie: true, isSeeded: true)

        // 5 — All dim (just a note).
        var farewell = Take(createdAt: at(-10), modifiedAt: at(-10),
                            bodyText: "Delete these when you're ready. Your Takes are already waiting.",
                            isSeeded: true)

        // Ensure the floor invariant holds on each.
        note.normaliseActivityFloor()
        task.normaliseActivityFloor()
        reminder.normaliseActivityFloor()
        obie.normaliseActivityFloor()
        farewell.normaliseActivityFloor()

        return [note, task, reminder, obie, farewell]
    }
}
