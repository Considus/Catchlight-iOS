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
    /// Build the five seed Takes in natural chronological (lesson) order — Note is
    /// oldest, Delete newest. Under the DEFAULT timeline order (TakeSort = "Oldest
    /// first", owner 2026-06-16) this reads top → bottom Note · Task · Reminder ·
    /// Delete — the intended teaching sequence — with the Obie pinned above; choosing
    /// "Newest first" in Settings simply inverts the list.
    public static func make(now: Date = Date()) -> [Take] {
        // Anchor to millisecond precision (the canonical wire format) so seed Takes
        // serialise bit-exactly. Offsets are whole seconds, keeping the .000 ms.
        let anchored = ISO8601.date(from: ISO8601.string(from: now)) ?? now
        func at(_ offset: TimeInterval) -> Date { anchored.addingTimeInterval(offset) }

        // 1 — Note (NW active by default). OLDEST → top under the Oldest-first default.
        var note = Take(createdAt: at(-50), modifiedAt: at(-50),
                        blocks: [.textLine("A Take is like memory, the place to keep your ideas and it's simply easy. Try touching the Iris on a Take, you'll see how effortless shaping a Take really is. Make it an Obie, task or add a reminder - do all of them or none of them, you're in control.")],
                        isSeeded: true)

        // 2 — Task (NE). A Task is a Take carrying a check item (D-034) — that check
        // block is what lights the Task quadrant. The seed leads with a line of prose
        // (the lesson) then a real sample check item beneath it (owner: "prose + sample
        // tickbox"), so it reads like a genuine task rather than a checkbox on an essay.
        var task = Take(createdAt: at(-40), modifiedAt: at(-40),
                        blocks: [
                            .textLine("Sometimes you need more structure, so when you need a list or plan to work from, add a task to your Take, yes, any Take, and give yourself time."),
                            .checkItem("Give yourself time to act")
                        ],
                        isSeeded: true)

        // 3 — Reminder (SW). A representative future reminder time.
        var reminder = Take(createdAt: at(-30), modifiedAt: at(-30),
                            blocks: [.textLine("When timing is everything, use a reminder. These can be added to any Take; doesn't matter if it's a note, a task or both. When you need to be nudged, poked or pushed, reminders are invaluable.")],
                            isSeeded: true)
        reminder.timeReminder = TimeReminder(
            scheduledDate: at(60 * 60 * 24),   // ~tomorrow; user can change or clear
            notificationIdentifier: reminder.id.uuidString
        )

        // 4 — Obie (SE, glow). The single north-star Take — pinned above the list, so
        // its timestamp only keeps the returned array monotonic.
        var obie = Take(createdAt: at(-20), modifiedAt: at(-20),
                        blocks: [.textLine("Only one Take is ever an Obie, that special memory or activity that's above all others. That's because you can only ever have one thought that's your most important and this is where it lives, always.")],
                        isObie: true, isSeeded: true)

        // 5 — All dim (just a note). NEWEST → bottom under the Oldest-first default.
        var farewell = Take(createdAt: at(-10), modifiedAt: at(-10),
                            blocks: [.textLine("Delete these introductory Takes whenever you're ready, easy as swiping left on a Take. This is your Catchlight, use it in the way that fits you perfectly. Oh and, if you need to check out customisation and settings, swipe up from the button area, below.")],
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
