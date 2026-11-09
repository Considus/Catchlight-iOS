//
//  TimelineBeam.swift
//  Catchlight (iOS app target)
//
//  The timeline's line and the Iris that sits on it. Both are flat: the line is a
//  single 1.5pt stroke in `ckSpine`, and each Take's Iris sits on it, its filled
//  inside hiding the line where the two cross.
//

import SwiftUI
import CatchlightCore

// 🚨 NO `.accessibilityHidden(true)` ON THE VIEWS IN THIS FILE — NOT ON THEIR BODIES
// AND NOT AT THEIR CALL SITES. Every struct here is pure shape/canvas drawing, which
// vends NO VoiceOver element by itself. On iOS 18.6/26.3 the hide modifier does the
// opposite of its name on such views: it MATERIALIZES an anonymous, selectable element
// and then fails to hide it (measured by in-process AX-tree dump, audit 2026-08 §15 —
// each hidden site vended an element; each removal removed it). The owner's device pass
// photographed exactly these leaks.

// MARK: - The line

/// The timeline's vertical line, centred in its frame.
struct TimelineLine: View {
    /// The LAYOUT footprint. Callers place the line by its centre (`x - width / 2`);
    /// the visible stroke inside it is `strokeWidth`.
    static let width: CGFloat = 36
    static let strokeWidth: CGFloat = 1.5

    var body: some View {
        Rectangle()
            .fill(Color.ckSpine)
            .frame(width: Self.strokeWidth)
            .frame(width: Self.width)
            .allowsHitTesting(false)
    }
}

// MARK: - The Iris on the line

/// The Iris as it appears ON THE TIMELINE: flat, sitting on the line.
///
/// 🚨 BOTH timeline rows must use this. There are two of them and it is easy to
/// believe there is one: the recycling `TimelineReadCell` draws every scrolling Take,
/// and the SwiftUI `TakeRowView` draws the PINNED OBIE (via `DailiesView.rowContent`).
/// Keeping the drawing in one view stops the two rows drifting apart.
///
/// The caller owns the card behind it and the gestures on top; this view is pure
/// rendering and takes no touches.
struct TimelineIris: View {
    let take: Take
    var diameter: CGFloat = CatchlightLayout.circleDiameter

    var body: some View {
        IrisView(take: take, diameter: diameter)
            .allowsHitTesting(false)
    }
}

#Preview("Line, Dark") {
    ZStack { Color.ckGround; TimelineLine().frame(maxHeight: .infinity) }
        .preferredColorScheme(.dark)
}

#Preview("Line, Light") {
    ZStack { Color.ckGround; TimelineLine().frame(maxHeight: .infinity) }
        .preferredColorScheme(.light)
}
