//
//  TakeCardStyle.swift
//  Catchlight (iOS app target) — Take colour/border system 2026-06-18
//
//  The card's colour treatment, derived ONCE from a Take (+ the active colour
//  scheme) and shared by every view that draws a Take-card — the read-only
//  `TakeCardSurface`, the shared editing card `TakeEditCard` (Dailies + Storyboard),
//  and `LockedCaptureView`'s capture card — so
//  read↔edit never drift and the precedence lives in one place.
//
//  A TAKE CARD IS FLAT (redesign): no shadow, in either appearance. Its edge is the border
//  below, and a plain note's is the `line` token, so a card never merges into the page.
//
//  Owner spec 2026-06-18 — two independent axes:
//
//    • SURFACE = emphasis. Dark (`ckCardObieSurface`) if the Take is Important (the
//      Obie always is, sticky); else the standard light `ckSurface`.
//
//    • BORDER = state, by precedence (first match wins):
//        overdue            → ruby   (`ckCardOverdueBorder`; the ONLY override of gold)
//        Obie               → gold   (`ckCardObieBorder`; Obie identity, persists in
//                                      every state except an overdue reminder)
//        done               → grey   (`ckCardDoneBorder` == `ckTextComplete` grey)
//        active task        → Task-quadrant colour   (same source as the Iris)
//        active reminder    → Remind-quadrant colour  (same source as the Iris)
//        else (plain note)  → the `line` token (a quiet edge, the same 0.75pt stroke, so
//                                      every card is one size)
//
//  The active borders read straight from `Quadrant`, so the card edge is the SAME
//  colour the Iris uses for that activity, by construction (owner: "use the colour
//  we use in the Iris"). A done Take is never "overdue" (done suppresses overdue), so
//  a done Obie keeps its gold border and only greys its text.
//

import SwiftUI
import CatchlightCore

struct TakeCardStyle {
    /// The card's border stroke width — one knob, shared by `TakeCardSurface` and the
    /// inline editor so they can't drift. 0.75pt (owner 2026-06-18: halved from 1.5pt
    /// to make the state colour a subtle HINT of an edge rather than an objective
    /// border). The invisible note border reserves this same width so all cards stay
    /// one size.
    static let borderWidth: CGFloat = 0.75
    /// Every Take card's corner radius (redesign: the one shared radius), read by each
    /// shape that has to sit exactly on a card: its surface, border, tap area and flash.
    static let cornerRadius: CGFloat = CatchlightLayout.surfaceRadius

    /// Card background fill.
    let surface: Color
    /// Stroke colour (drawn at `borderWidth`; equals `surface` when the card has no
    /// visible border).
    let border: Color
    /// First-line / body text colour.
    let bodyText: Color
    /// Reminder past its time and NOT done — drives the ruby *italic* subtext and the
    /// slightly stronger Daylight shadow.
    let isOverdue: Bool
    /// A fully-ticked Task or a reminder marked done — the subtext recedes to the
    /// done grey (and upright, since italic is reserved for overdue).
    let isDone: Bool

    init(take: Take, scheme: ColorScheme, now: Date = Date()) {
        // Overdue is single-sourced on `TimeReminder.isOverdue` so the card edge and the
        // "Expired" Sequence filter can never disagree (owner 2026-06-21). A repeating
        // reminder is never overdue — its anchor sits in the past by design yet it always
        // has a next occurrence ahead.
        let overdue = take.timeReminder?.isOverdue(now: now) ?? false
        let done = take.isMarkedDone

        let surfaceColor: Color = take.isImportant ? .ckCardObieSurface : .ckSurface
        self.surface = surfaceColor

        if overdue {
            self.border = .ckCardOverdueBorder
        } else if take.isObie {
            self.border = .ckCardObieBorder
        } else if done {
            self.border = .ckCardDoneBorder
        } else if take.isTask {
            self.border = Quadrant.task(scheme)
        } else if take.timeReminder != nil || take.locationReminder != nil {
            // A "where" gets the Remind border exactly like a "when" (2026-07-01,
            // place/time parity). Places never go OVERDUE — a geofence has no due
            // instant to be past — so the ruby branch above stays time-only.
            self.border = Quadrant.reminder(scheme)
        } else {
            self.border = .ckLine
        }

        self.bodyText = done ? .ckTextComplete : (take.isObie ? .ckTextObie : .ckTextPrimary)
        self.isOverdue = overdue
        self.isDone = done
    }
}
