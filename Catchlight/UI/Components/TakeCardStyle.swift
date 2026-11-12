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
//    • SURFACE = emphasis. Every Important Take, the Obie included, takes
//      `ckCardImportantSurface` (its own shade in Daylight, owner 2026-11-12: "an Obie, by
//      its very nature, is the most important"); else the standard `ckSurface`.
//
//    • BORDER, by precedence (first match wins; owner 2026-11-12, "Option 1"):
//        overdue            → ruby   (`ckCardOverdueBorder`)
//        Obie               → lit    (`ckCardObieBorder`, the strongest edge)
//        Important          → `ckCardImportantBorder`, a mid edge between line and lit
//        else               → the `line` token: notes, Tasks, reminders and done Takes
//  Every edge is the same 0.75pt stroke, so every card is one size. A done Take is never
//  "overdue" (done suppresses overdue), so a done Obie keeps its edge and only greys its text.
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

        let surfaceColor: Color = take.isImportant ? .ckCardImportantSurface : .ckSurface
        self.surface = surfaceColor

        if overdue {
            self.border = .ckCardOverdueBorder
        } else if take.isObie {
            self.border = .ckCardObieBorder
        } else if take.isImportant {
            self.border = .ckCardImportantBorder
        } else {
            self.border = .ckLine
        }

        self.bodyText = done ? .ckTextComplete : (take.isObie ? .ckTextObie : .ckTextPrimary)
        self.isOverdue = overdue
        self.isDone = done
    }
}

extension TakeCardStyle {
    /// The style of a plain note, the card most Takes are: for a screen that draws something
    /// as a Take card without being a Take.
    static func plain(scheme: ColorScheme) -> TakeCardStyle {
        TakeCardStyle(take: Take(blocks: [.textLine("")]), scheme: scheme)
    }
}

extension View {
    /// A Take card's face: its fill and its border, at the card radius and border width. The
    /// timeline row draws the same two shapes in `TakeCardSurface`.
    func takeCardFace(_ style: TakeCardStyle) -> some View {
        background(
            RoundedRectangle(cornerRadius: TakeCardStyle.cornerRadius, style: .continuous)
                .fill(style.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TakeCardStyle.cornerRadius, style: .continuous)
                .strokeBorder(style.border, lineWidth: TakeCardStyle.borderWidth)
        )
    }
}
