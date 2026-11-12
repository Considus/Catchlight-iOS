//
//  TakeLabelLane.swift
//  Catchlight (iOS app target) — Take label lane 2026-06-18
//
//  A slim "label lane" hugging a Take card's LEFT edge — the owner's reusable
//  container for at-a-glance labels. It occupies the strip between the card's left
//  edge and the Iris (so the Iris always stays in the clear), runs the card's
//  height, and mirrors the card's left corner radii on its right side (a slim rounded
//  pill, not cut flat).
//
//  No card draws the lane today: the sideways "OVERDUE" word is `TakeStateWordStrip`
//  (owner 2026-11-12). Kept for the colour-label chip below; revisit (wire it or delete
//  it) when colour labels are built.
//   • `.colourChip` — FUTURE (user-assignable labels, its own release): the container
//     FILLED with the label colour + the Take's shadow so it floats just above the
//     card, inset ~10pt from the edges. Defined here so it drops in without
//     re-plumbing the row. See [[catchlight-take-colour-system]].
//
//  Rendered as a leading overlay on `TakeCardSurface`, so it rides with the card
//  (incl. the swipe offset) and appears everywhere the card does.
//

import SwiftUI

struct TakeLabelLane: View {
    enum Content {
        case none
        // FUTURE — user label: the lane filled with the colour + Take shadow, a
        // floating chip (DEMO-wired now; a later release adds the data model + UI).
        case colourChip(Color)
    }

    var content: Content
    /// Lane width = the strip from the card's left edge to the Iris's left edge
    /// (`irisInset`), so the lane never reaches the Iris.
    var width: CGFloat = CatchlightLayout.irisInset
    /// The colour chip's inset — equal on left, top, and bottom (owner 2026-06-18).
    static let chipGap: CGFloat = 4

    var body: some View {
        switch content {
        case .none:
            // Reserves nothing visible (it's an overlay; non-labelled cards are
            // untouched).
            Color.clear.frame(width: width)
        case .colourChip(let colour):
            // FUTURE user label (DEMO render): a slim coloured pill hugging the left
            // edge with an EQUAL gap on left/top/bottom, flat (no shadow).
            CatchlightShape.control
                .fill(colour)
                .frame(width: max(0, width - Self.chipGap))
                .frame(maxHeight: .infinity)
                .padding(.vertical, Self.chipGap)
                .padding(.leading, Self.chipGap)
                .accessibilityHidden(true)
        }
    }
}
