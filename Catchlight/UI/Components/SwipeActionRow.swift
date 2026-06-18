//
//  SwipeActionRow.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  Horizontal swipe actions for a timeline row. The Dailies timeline is a
//  `LazyVStack` inside a `ScrollView` (NOT a `List`), so SwiftUI's `.swipeActions`
//  modifier is unavailable; this rebuilds the iOS "swipe to reveal, full-swipe to
//  commit" interaction by hand.
//
//    • swipe LEFT  → reveals the TRAILING action (Delete). Full swipe commits.
//    • swipe RIGHT → reveals the LEADING  action (Mark done). Full swipe commits.
//
//  DESIGN (owner device review, 2026-06-16): the action is a full-bleed colour
//  fill that LIVES BEHIND the card and is revealed as the card slides over it —
//  not a floating button beside the card. Consequences that match the owner's
//  asks:
//    • The fill is pinned to the SCREEN edge and grows with the swipe, so it
//      "stretches from the edge" rather than popping into existence.
//    • It tucks `tuckUnder` pt UNDER the card; the card's opaque rounded surface
//      is on top, so the visible boundary is the card's own rounded edge — no gap,
//      no corner triangle.
//    • Only the CARD slides: `content` is a closure given the live offset, and the
//      caller applies it to the card alone (NOT the Iris), so the Iris stays on the
//      spine — preserving the timeline "wire" (and the future rings-on-a-wire).
//
//  Only the sides supplied are enabled — Done is omitted on non-Task rows by
//  passing `leading: nil`. The row's long-press context menu remains the
//  VoiceOver / fallback path.
//
//  Single-open coordination via the shared `openRowID`: opening one row closes any
//  other. Tunables are gathered at the top for device-review nudging.
//

import SwiftUI

/// One side's swipe action.
struct SwipeAction {
    enum Style { case destructive, standard }
    var title: String
    var systemImage: String
    var tint: Color
    var style: Style
    var perform: () -> Void
}

struct SwipeActionRow<Content: View>: View {
    let id: UUID
    var leading: SwipeAction? = nil     // revealed by a rightward swipe
    var trailing: SwipeAction? = nil    // revealed by a leftward swipe
    @Binding var openRowID: UUID?
    /// The card's own leading / trailing margins inside this row (the fill spans
    /// from the card's surface edge out to the screen edge, so it needs them).
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0
    /// Vertical inset so the fill matches the CARD's height, not the full row band
    /// (the card sits inside the band by its own top/bottom padding — 6 in TakeRow).
    var contentVerticalInset: CGFloat = 0
    /// How far the fill tucks UNDER the card (≈ the card corner radius) so the card
    /// masks its inner edge and the boundary is the card's rounded corner.
    var tuckUnder: CGFloat = 12
    /// Card slide that settles "open" (the resting static-button width). Default 42
    /// (timeline, owner 2026-06-16); the list Angle passes a larger value (owner
    /// 2026-06-18: the resting Delete button read too small there).
    var actionWidth: CGFloat = 42
    /// Receives the live horizontal offset; the caller applies it to the CARD only.
    @ViewBuilder var content: (CGFloat) -> Content

    // MARK: Tunables (device review may nudge these)
    private let revealSnapFraction: CGFloat = 0.55   // settle open past this × actionWidth
    private let commitFraction: CGFloat = 0.5        // full-swipe commit past this × row width
    /// The fill fades 0→1 over the first `fadeInDistance` pt of swipe, so the card's
    /// side-margin strip materialises smoothly instead of popping (owner 2026-06-16).
    private let fadeInDistance: CGFloat = 24

    @State private var offset: CGFloat = 0
    @State private var restOffset: CGFloat = 0
    @State private var rowWidth: CGFloat = 1

    var body: some View {
        ZStack {
            actionLayer
            content(offset)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { rowWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, w in rowWidth = w }
                    }
                )
                .overlay {
                    // An OPEN row: a tap on the CARD closes it (rather than opening
                    // the editor). The catcher covers ONLY the card's footprint and
                    // moves with it, so taps on the revealed fill still reach the fill
                    // and commit (the bug was a full-width catcher swallowing them).
                    if offset != 0 { closeCatcher }
                }
                // UIKit-bridged pan, NOT a SwiftUI DragGesture (owner bug 2026-06-16).
                // A SwiftUI gesture (even `.simultaneousGesture`) only coordinates with
                // OTHER SwiftUI gestures — never the ScrollView's own UIKit pan. So once
                // the swipe claimed the touch, a mid-stroke switch to vertical couldn't
                // reach the scroll and the page froze until you lifted. This recognizer's
                // delegate fixes both ends: it only BEGINS on a horizontal-led pan (so
                // vertical scrolls are never claimed) and returns
                // `shouldRecognizeSimultaneouslyWith = true` (so the scroll's pan keeps
                // tracking and vertical motion scrolls even after a partial swipe).
                .gesture(HorizontalSwipePan(onChange: applySwipe, onEnd: endSwipe))
        }
        .onChange(of: openRowID) { _, newID in
            if newID != id, offset != 0 { close() }
        }
    }

    /// Transparent tap-to-close layer sized to the card and offset with it, so the
    /// revealed fill (outside the card) stays tappable for commit.
    private var closeCatcher: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: max(0, rowWidth - leadingInset - trailingInset))
                .contentShape(Rectangle())
                .onTapGesture { close() }
            Spacer(minLength: 0)
        }
        .padding(.leading, leadingInset)
        .offset(x: offset)
    }

    // MARK: The action fill (behind the card)

    @ViewBuilder
    private var actionLayer: some View {
        HStack(spacing: 0) {
            if let leading, offset > 0 {
                // From the screen's LEADING edge to just under the card's left edge.
                fill(leading, width: leadingInset + offset + tuckUnder, edge: .leading)
                Spacer(minLength: 0)
            } else if let trailing, offset < 0 {
                Spacer(minLength: 0)
                // From just under the card's right edge to the screen's TRAILING edge.
                fill(trailing, width: trailingInset - offset + tuckUnder, edge: .trailing)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, contentVerticalInset)
    }

    private func fill(_ action: SwipeAction, width: CGFloat, edge: HorizontalEdge) -> some View {
        ZStack(alignment: edge == .leading ? .leading : .trailing) {
            action.tint
            // Label hugged to the OUTER (screen) edge so it rides there as the fill
            // grows AND clears the Iris, which stays on the spine and floats over the
            // leading fill (owner 2026-06-16 — the Done label was under the Iris).
            VStack(spacing: 4) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(action.title)
                    .font(CatchlightFont.ui(.medium, size: 11, relativeTo: .caption))
            }
            .foregroundStyle(.white)
            .padding(edge == .leading ? .leading : .trailing, 8)
        }
        .frame(width: max(0, width))
        .frame(maxHeight: .infinity)
        .clipped()
        // Fade in over the first `fadeInDistance` pt so the side-margin strip
        // materialises smoothly rather than popping at the start of the swipe.
        .opacity(min(1, abs(offset) / fadeInDistance))
        .accessibilityElement()
        .accessibilityLabel(action.title)
        .accessibilityAddTraits(.isButton)
        .onTapGesture { commit(action) }
    }

    // MARK: Gesture

    /// Live swipe — `tx` is the recognizer's cumulative horizontal translation. The
    /// recognizer only fires this for horizontal-led pans (its delegate gates the
    /// start), so no vertical guard is needed here; vertical motion is left to the
    /// ScrollView, which tracks simultaneously.
    private func applySwipe(_ tx: CGFloat) {
        offset = clamp(restOffset + tx)
        if offset != 0, openRowID != id { openRowID = id }
    }

    /// Release — full-swipe commits, a shorter swipe settles open, otherwise closes.
    private func endSwipe(_ tx: CGFloat) {
        let dx = offset
        let commitDistance = max(rowWidth * commitFraction, actionWidth * 1.6)
        if trailing != nil, dx <= -commitDistance {
            commit(trailing!)
        } else if leading != nil, dx >= commitDistance {
            commit(leading!)
        } else if trailing != nil, dx <= -(actionWidth * revealSnapFraction) {
            settle(to: -actionWidth)
        } else if leading != nil, dx >= actionWidth * revealSnapFraction {
            settle(to: actionWidth)
        } else {
            close()
        }
    }

    /// Clamp the live offset to the available side, rubber-banding past the rest
    /// width so an over-swipe resists rather than tracking the finger 1:1.
    private func clamp(_ x: CGFloat) -> CGFloat {
        var v = x
        if v > 0 {
            guard leading != nil else { return 0 }
            if v > actionWidth { v = actionWidth + (v - actionWidth) * 0.5 }
        } else if v < 0 {
            guard trailing != nil else { return 0 }
            if v < -actionWidth { v = -actionWidth + (v + actionWidth) * 0.5 }
        }
        return v
    }

    // MARK: Settle / commit

    private func settle(to value: CGFloat) {
        withAnimation(.snappy(duration: 0.25)) { offset = value }
        restOffset = value
        openRowID = id
    }

    private func close() {
        withAnimation(.snappy(duration: 0.25)) { offset = 0 }
        restOffset = 0
        if openRowID == id { openRowID = nil }
    }

    /// A fill tap or a full-swipe release both land here.
    private func commit(_ action: SwipeAction) {
        switch action.style {
        case .destructive:
            // Slide the card off the leaving edge, then perform (which removes the
            // row); animate the perform so the list collapses smoothly behind it.
            let target = (offset <= 0 ? -1 : 1) * (rowWidth + 200)
            withAnimation(.snappy(duration: 0.22)) {
                offset = target
            } completion: {
                withAnimation(.snappy(duration: 0.2)) { action.perform() }
                offset = 0
                restOffset = 0
                if openRowID == id { openRowID = nil }
            }
        case .standard:
            // Non-destructive (toggle done) — the row stays; perform and close.
            action.perform()
            close()
        }
    }
}

// MARK: - UIKit-bridged horizontal swipe pan

/// A horizontal swipe pan bridged from UIKit (iOS 18 `UIGestureRecognizerRepresentable`)
/// so its delegate can coordinate with the enclosing ScrollView's OWN pan recognizer —
/// something a SwiftUI gesture cannot do. The delegate:
///   • only lets the pan BEGIN when the stroke is horizontal-led, so vertical scrolls
///     are never claimed; and
///   • allows simultaneous recognition with every other recognizer (the scroll's pan,
///     the Iris's tap/long-press), so the scroll keeps tracking the whole touch and
///     vertical motion scrolls even after a partial swipe — without lifting the finger.
/// Taps/long-presses are unaffected: a pan only begins on movement.
struct HorizontalSwipePan: UIGestureRecognizerRepresentable {
    /// Cumulative horizontal translation while the swipe is active.
    var onChange: (CGFloat) -> Void
    /// Final horizontal translation on release / cancel.
    var onEnd: (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let tx = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .changed:
            onChange(tx)
        case .ended, .cancelled, .failed:
            onEnd(tx)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        // Begin only for horizontal-led pans → vertical scrolls win outright.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y)
        }

        // Coexist with the ScrollView's pan (and the Iris recognizers): returning true
        // from our delegate is enough to guarantee simultaneous recognition, so the
        // scroll never gets grabbed mid-stroke.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
