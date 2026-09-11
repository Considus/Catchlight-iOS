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
    /// What VoiceOver says instead of `text`, where the two must differ.
    ///
    /// 🚨 The drawn hints name TOUCH gestures that do not exist for a VoiceOver user:
    /// "Tap the Iris", "Swipe up here", "Long-press here". A swipe up is swallowed by
    /// VoiceOver entirely, and a long-press never reaches the app. So the visible text
    /// is right for a finger and wrong for the cursor, and the two need different words
    /// (owner, 2026-09-10).
    ///
    /// Naming the real route also makes dismissal less pressing: the hint stops being
    /// something to get rid of and becomes the instruction for reaching the next step.
    /// Nil means the drawn text is already correct for both.
    var voiceOverText: String?
    var arrowEdge: Edge = .bottom
    /// Where the arrow sits ALONG a top/bottom edge. `.center` (default) is the
    /// classic centred arrow. `.leading` parks it near the bubble's left so the
    /// bubble extends RIGHT of the anchor — used for the Add hint, whose button is
    /// near the screen's left edge, so a centred bubble would clip off-screen
    /// (owner 2026-06-15). Ignored for `.leading`/`.trailing` arrow edges.
    var arrowAlignment: HorizontalAlignment = .center
    var maxWidth: CGFloat = 220
    @AccessibilityFocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var widthScale: CGFloat = 1
    @Environment(\.dynamicTypeSize) private var dynamicSize

    /// Room actually available from this bubble's LEADING EDGE to the screen's trailing
    /// margin. `.infinity` for a bubble laid out near x = 0, where the ceiling below is
    /// sufficient on its own.
    ///
    /// 🚨 DT17: the cap below is absolute and silently assumed an origin near the left edge.
    /// An Iris-anchored tooltip starts at `spineX + radius + 5`, roughly 87pt in, so a 320pt
    /// bubble needed 407pt on a 393pt screen and was clipped mid-word at the largest text
    /// sizes. A width cap is only meaningful together with where the thing starts.
    var availableWidth: CGFloat = .infinity

    /// The cap. Scales with the text so a single word above Large is never wider than the
    /// bubble, with a ceiling that keeps it inside the narrowest supported screen, and never
    /// wider than the room its origin actually leaves.
    private var bubbleWidth: CGFloat {
        // `availableWidth` is room for the whole BUBBLE; this cap applies to the TEXT, which
        // sits inside `horizontalPadding` on each side. Subtract it here rather than at the
        // call site: the padding is this view's business and a caller cannot be expected to
        // know it.
        min(maxWidth * widthScale, 320, availableWidth - Self.horizontalPadding * 2)
    }

    private static let horizontalPadding: CGFloat = 14

    var body: some View {
        Text(text)
            .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .body))
            .foregroundStyle(Color.ckTooltipText)
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
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.ckTooltipFill)
                    OrientationTooltipArrow(edge: arrowEdge)
                        .fill(Color.ckTooltipFill)
                        .frame(width: 14, height: 8)
                        .modifier(ArrowPlacement(edge: arrowEdge, horizontal: arrowAlignment))
                }
            )
            .shadow(color: Color.black.opacity(0.18), radius: 8, y: 2)
            // 🚨 `.combine`, not the bare `.accessibilityElement()` this used to call.
            // MEASURED (DockOrderProbeTests, 2026-09-08): the bare form created the
            // container but did NOT suppress the Text inside it, so one tooltip vended
            // TWO elements with the same words — an `.other` at the bubble's frame
            // (12, 713.7) 173x46.3 and a `.staticText` at the text's own inset frame
            // (26, 723.7) 145x18.3. Every other element on that screen vends once.
            //
            // Two adjacent stops reading the identical sentence is what "I can't get
            // past the tooltip" is from the inside, and it is V43's double utterance.
            // `.combine` merges the subtree into a single element instead of laying a
            // container over a child that is still vending.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(voiceOverText ?? text)
            // Audit 2026-08, V25: the hints appear silently — a VoiceOver user
            // gets no signal a tooltip arrived, and its element sits wherever the
            // walk puts it. Announce the text on appearance, component-level so
            // every hint site is covered. Placement in the VO order is the
            // device-gated half of the finding and is not changed here.
            .accessibilityFocused($isFocused)
            .onAppear {
                // 🚨 TAKE THE CURSOR, do not merely announce (owner 2026-09-11: "the tips
                // are the task, so let's fix it for all"). A hint that only announces
                // leaves the user to go and find it, and these hints ARE the next step
                // rather than commentary on it.
                //
                // Deferred through `VoiceOverFocus`: setting focus in the same update
                // that creates the element races it into the accessibility tree, and
                // SwiftUI reports nothing when the request lands early.
                //
                // 📌 That race is very likely why this tooltip's announcement has looked
                // unreliable all along. It spoke on arrival and then never again on
                // re-focus, and a day went into attributing that to the Add Button
                // swallowing its label. The post is kept as well as the focus move:
                // focus makes VoiceOver read the element, and the announcement covers the
                // case where the cursor is already somewhere the user chose to be.
                VoiceOverFocus.takeFocus(from: "tooltip.onAppear") { isFocused = true }
                A11yDiag.post(.announcement, argument: voiceOverText ?? text,
                              from: "tooltip.onAppear")
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
