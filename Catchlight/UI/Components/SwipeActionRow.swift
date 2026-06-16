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
    /// Receives the live horizontal offset; the caller applies it to the CARD only.
    @ViewBuilder var content: (CGFloat) -> Content

    // MARK: Tunables (device review may nudge these)
    private let actionWidth: CGFloat = 84            // card slide that settles "open"
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
                .gesture(dragGesture)
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

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                // Horizontal-dominant only — vertical-led drags are ignored so the
                // ScrollView keeps scrolling. (PRIMARY device-review risk: if the
                // vertical scroll ever feels "grabbed," switch `.gesture` →
                // `.simultaneousGesture` or raise the dominance ratio here.)
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = clamp(restOffset + value.translation.width)
                if offset != 0, openRowID != id { openRowID = id }
            }
            .onEnded { _ in
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
