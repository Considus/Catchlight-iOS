//
//  SwipeActionRow.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  Horizontal swipe actions for a timeline row. The Dailies timeline is a
//  `LazyVStack` inside a `ScrollView` (NOT a `List`), so SwiftUI's `.swipeActions`
//  modifier is unavailable; this rebuilds the iOS-standard "short-swipe reveals a
//  button, full-swipe commits" interaction by hand around the existing row.
//
//    • swipe LEFT  → reveals the TRAILING action (Delete). Full swipe commits.
//    • swipe RIGHT → reveals the LEADING  action (Mark done). Full swipe commits.
//
//  Only the sides supplied are enabled — Done is omitted on non-Task rows by
//  passing `leading: nil`. The row's long-press context menu remains the
//  VoiceOver / fallback path; this is a discoverability ENHANCEMENT, not the only
//  route to either action.
//
//  Single-open coordination is via the shared `openRowID` binding: opening one
//  row closes any other. The interaction tunables (reveal width, snap + commit
//  thresholds) are gathered at the top for device-review nudging.
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
    @ViewBuilder var content: Content

    // MARK: Tunables (device review may nudge these)
    private let actionWidth: CGFloat = 84
    private let revealSnapFraction: CGFloat = 0.55   // settle open past this × actionWidth
    private let commitFraction: CGFloat = 0.5        // full-swipe commit past this × row width

    @State private var offset: CGFloat = 0
    @State private var restOffset: CGFloat = 0
    @State private var rowWidth: CGFloat = 1

    var body: some View {
        ZStack {
            actionLayer
            content
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { rowWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, w in rowWidth = w }
                    }
                )
                .offset(x: offset)
                .overlay {
                    // An OPEN row swallows taps to CLOSE, rather than passing the tap
                    // through to the card (which would open the editor).
                    if offset != 0 {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                    }
                }
                .gesture(dragGesture)
        }
        .onChange(of: openRowID) { _, newID in
            if newID != id, offset != 0 { close() }
        }
    }

    // MARK: Revealed action buttons

    @ViewBuilder
    private var actionLayer: some View {
        HStack(spacing: 0) {
            if let leading, offset > 0 {
                button(for: leading, revealed: offset, edge: .leading)
                Spacer(minLength: 0)
            } else if let trailing, offset < 0 {
                Spacer(minLength: 0)
                button(for: trailing, revealed: -offset, edge: .trailing)
            }
        }
    }

    private func button(for action: SwipeAction, revealed: CGFloat, edge: HorizontalEdge) -> some View {
        Button {
            commit(action)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(action.title)
                    .font(CatchlightFont.ui(.medium, size: 11, relativeTo: .caption))
            }
            .foregroundStyle(.white)
            .frame(maxHeight: .infinity)
            // Track the reveal so the fill exactly covers the strip the card
            // vacates — and keeps covering it while rubber-banding past it.
            .frame(width: max(actionWidth, revealed))
            .background(action.tint)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: edge == .leading ? 12 : 0,
                    bottomLeadingRadius: edge == .leading ? 12 : 0,
                    bottomTrailingRadius: edge == .trailing ? 12 : 0,
                    topTrailingRadius: edge == .trailing ? 12 : 0,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
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

    /// A revealed-button tap or a full-swipe release both land here.
    private func commit(_ action: SwipeAction) {
        switch action.style {
        case .destructive:
            // Slide the card off the leaving edge, then perform (which removes the
            // row); animate the perform so the list collapses smoothly behind it.
            let target = (offset <= 0 ? -1 : 1) * (rowWidth + actionWidth)
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
