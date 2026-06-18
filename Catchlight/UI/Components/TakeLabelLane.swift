//
//  TakeLabelLane.swift
//  Catchlight (iOS app target) — Take label lane 2026-06-18
//
//  A slim "label lane" hugging a Take card's LEFT edge — the owner's reusable
//  container for at-a-glance labels. It occupies the strip between the card's left
//  edge and the Iris (so the Iris + spine always stay in the clear), runs the card's
//  height, and mirrors the card's left corner radii on its right side (a slim rounded
//  pill, not cut flat).
//
//  ONE container, two render modes (owner 2026-06-18):
//   • `.systemText` — a small, glanceable VERTICAL (−90°) label in the Time-note
//     font/size (e.g. ruby "OVERDUE"); text only, NO fill. Reinforces a system state
//     quietly without being loud. The only mode used today.
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
        /// Vertical text label (string + colour), Time-note font. No fill.
        case systemText(String, Color)
        // FUTURE — user label: the lane filled with the colour + Take shadow, a
        // floating chip. case colourChip(Color)
    }

    var content: Content
    /// Lane width = the strip from the card's left edge to the Iris's left edge
    /// (`cardSpineInset` − Iris radius), so the lane never reaches the Iris/spine.
    var width: CGFloat = CatchlightLayout.cardSpineInset - CatchlightLayout.circleDiameter / 2

    var body: some View {
        switch content {
        case .none:
            // Reserves nothing visible (it's an overlay; non-labelled cards are
            // untouched).
            Color.clear.frame(width: width)
        case .systemText(let text, let colour):
            Text(text)
                // Matches the reminder Time-note scale (DM Sans 11pt medium).
                .font(CatchlightFont.ui(.medium, size: 11, relativeTo: .caption))
                .foregroundStyle(colour)
                .lineLimit(1)
                .fixedSize()                       // lay out at natural size, THEN rotate
                .rotationEffect(.degrees(-90))     // reads bottom-to-top, glanceable
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)         // the row label already speaks the state
        }
    }
}
