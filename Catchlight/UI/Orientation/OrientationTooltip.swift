//
//  OrientationTooltip.swift
//  Catchlight (iOS app target) — Phase 6 UI, Task 3.13
//
//  The reusable bubble used by all four first-run orientation hints. A rounded
//  rect with a small triangular arrow pointing at the relevant UI element, sitting
//  lightly on top of the live UI (no dim overlay). Same component shape for every
//  hint so the visual vocabulary stays consistent.
//

import SwiftUI

struct OrientationTooltip: View {

    let text: String
    var arrowEdge: Edge = .bottom
    /// Where the arrow sits ALONG a top/bottom edge. `.center` (default) is the
    /// classic centred arrow. `.leading` parks it near the bubble's left so the
    /// bubble extends RIGHT of the anchor — used for the Add hint, whose button is
    /// near the screen's left edge, so a centred bubble would clip off-screen
    /// (owner 2026-06-15). Ignored for `.leading`/`.trailing` arrow edges.
    var arrowAlignment: HorizontalAlignment = .center
    var maxWidth: CGFloat = 220
    @ScaledMetric(relativeTo: .body) private var widthScale: CGFloat = 1
    @Environment(\.dynamicTypeSize) private var dynamicSize

    /// The cap. Scales with the text so a single word above Large is never wider than the
    /// bubble, with a ceiling that keeps it inside the narrowest supported screen.
    private var bubbleWidth: CGFloat { min(maxWidth * widthScale, 320) }

    var body: some View {
        Text(text)
            .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .body))
            .foregroundStyle(Color.ckTextPrimary)
            .multilineTextAlignment(.center)
            // 🚨 The caller applies `.fixedSize()` — BOTH axes — to escape the 44pt dock
            // button it overlays. That proposes nil×nil, and under a nil proposal
            // `.frame(maxWidth:)` clamps the WIDTH to the cap but reports the child's ideal
            // HEIGHT, which is the ONE-LINE height measured at the unclamped width. The text
            // then wrapped to two lines inside a bubble one line tall and the second line hung
            // outside the background (owner device report 2026-09-04, rounds 3 and 4).
            //
            // Reordering `.fixedSize` and `.frame` does NOT fix it: the caller's `.fixedSize()`
            // re-creates the same nil proposal one level up, which is why round 3's reorder
            // changed nothing on the device.
            //
            // A DEFINITE width removes the negotiation: the text is laid out at exactly this
            // width, so its height is computed for the width it will really have. Applied only
            // above Large — below it the cap is never reached, the bubble hugs its text, and
            // that tuned appearance is left exactly as it was.
            .frame(width: dynamicSize > .large ? bubbleWidth : nil)
            .frame(maxWidth: dynamicSize > .large ? nil : bubbleWidth)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.ckSurface)
                    OrientationTooltipArrow(edge: arrowEdge)
                        .fill(Color.ckSurface)
                        .frame(width: 14, height: 8)
                        .modifier(ArrowPlacement(edge: arrowEdge, horizontal: arrowAlignment))
                }
            )
            .shadow(color: Color.black.opacity(0.18), radius: 8, y: 2)
            .accessibilityElement()
            .accessibilityLabel(text)
            // Audit 2026-08, V25: the hints appear silently — a VoiceOver user
            // gets no signal a tooltip arrived, and its element sits wherever the
            // walk puts it. Announce the text on appearance, component-level so
            // every hint site is covered. Placement in the VO order is the
            // device-gated half of the finding and is not changed here.
            .onAppear {
                UIAccessibility.post(notification: .announcement, argument: text)
            }
    }
}

/// A tiny isosceles triangle pointing along the requested edge. Drawn in a 14×8
/// rect; rotated/positioned by `ArrowPlacement` so the same shape works for any edge.
private struct OrientationTooltipArrow: Shape {
    let edge: Edge

    func path(in rect: CGRect) -> Path {
        var p = Path()
        // Base triangle points down (apex at bottom-centre). ArrowPlacement rotates
        // and positions it for each edge so the apex sits flush against the bubble.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Positions and rotates the arrow so its apex pokes out of the requested bubble edge.
private struct ArrowPlacement: ViewModifier {
    let edge: Edge
    /// Along a top/bottom edge: `.center` centres the arrow; `.leading`/`.trailing`
    /// park it `arrowEdgeInset` in from that corner (so the bubble extends away).
    var horizontal: HorizontalAlignment = .center

    /// Arrow-CENTRE distance from the leading/trailing edge when not centred. 22pt
    /// lines the apex up with the centre of a 44pt control whose near edge aligns
    /// with the bubble's.
    private let arrowEdgeInset: CGFloat = 22

    func body(content: Content) -> some View {
        switch edge {
        case .top:
            content
                .rotationEffect(.degrees(180))
                .offset(y: -8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: topBottomAlignment(top: true))
                .offset(x: horizontalInset)
        case .bottom:
            content
                .offset(y: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: topBottomAlignment(top: false))
                .offset(x: horizontalInset)
        case .leading:
            content
                .rotationEffect(.degrees(90))
                .offset(x: -8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .trailing:
            content
                .rotationEffect(.degrees(-90))
                .offset(x: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }

    private func topBottomAlignment(top: Bool) -> Alignment {
        if horizontal == .leading  { return top ? .topLeading  : .bottomLeading }
        if horizontal == .trailing { return top ? .topTrailing : .bottomTrailing }
        return top ? .top : .bottom
    }

    /// Shift the arrow in from the corner so its CENTRE lands `arrowEdgeInset` from
    /// the edge (the arrow is 14pt wide, so its own centre is 7pt in when corner-aligned).
    private var horizontalInset: CGFloat {
        if horizontal == .leading  { return arrowEdgeInset - 7 }
        if horizontal == .trailing { return -(arrowEdgeInset - 7) }
        return 0
    }
}

#Preview("Tooltip — Night") {
    VStack(spacing: 40) {
        OrientationTooltip(text: "What's your first Take?", arrowEdge: .bottom)
        OrientationTooltip(text: "Tap the Iris to shape this Take.", arrowEdge: .leading)
        OrientationTooltip(text: "Swipe up here for settings.", arrowEdge: .bottom)
        OrientationTooltip(
            text: "This is your Obie — your one most important Take. It stays at the top of everything until it's done.",
            arrowEdge: .top
        )
    }
    .padding()
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}

#Preview("Tooltip — Daylight") {
    VStack(spacing: 40) {
        OrientationTooltip(text: "What's your first Take?", arrowEdge: .bottom)
        OrientationTooltip(text: "Tap the Iris to shape this Take.", arrowEdge: .leading)
    }
    .padding()
    .background(Color.ckBackground)
    .preferredColorScheme(.light)
}
