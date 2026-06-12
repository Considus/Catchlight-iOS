//
//  DockPillRow.swift
//  Catchlight (iOS app target)
//
//  Onboarding/paywall actions adopt the DOCK GEOMETRY (owner decision
//  2026-06-12, HiFi v1.7 internal v1.11.1/.2): a single pill button sits
//  exactly over the four dock-button slots — if the dock were visible, the
//  pill would hide all four buttons precisely. A pair of buttons splits the
//  pill: the leading button covers slots 1+2, the trailing button covers
//  slots 3+4, both fully rounded, separated by the grid's natural
//  inter-button gap.
//
//  The grid is the same one BottomDockView and CatchlightLayout.spineX derive
//  from: four equal slots inside `dockHorizontalPadding`, button diameter
//  `minTouchTarget` — so the pills inherit the 44pt HIG touch target and the
//  row occupies the dock's exact resting position (top 10 / bottom 8 padding).
//

import SwiftUI

/// The standard dock-geometry button label: Ember capsule + ckBackground text
/// (primary), or a ckTextPrimary@40% outline (secondary).
struct DockPill: View {
    let title: String
    var secondary: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CatchlightFont.ui(.medium, size: 15, relativeTo: .body))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 10)
                .foregroundStyle(secondary ? Color.ckTextPrimary : Color.ckBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if secondary {
                        Capsule().stroke(Color.ckTextPrimary.opacity(0.4), lineWidth: 1)
                    } else {
                        Capsule().fill(Color.ckAdd)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

extension View {
    /// The dock's soft bottom edge behind a pill row (HiFi v1.11.5, owner
    /// 2026-06-12): scrolling content fades out beneath the button zone
    /// instead of meeting a hard edge. Apply to the safeAreaInset content.
    func dockFadeBackground() -> some View {
        background(
            LinearGradient(stops: [
                .init(color: Color.ckBackground.opacity(0), location: 0),
                .init(color: Color.ckBackground.opacity(0.85), location: 0.28),
                .init(color: Color.ckBackground, location: 0.55)
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// One row on the dock grid. One child spans all four slots; two children
/// cover slots 1+2 and 3+4 with the grid's inter-button gap between them.
struct DockPillRow<Primary: View, Trailing: View>: View {
    private let primary: Primary
    private let trailing: Trailing?

    init(@ViewBuilder primary: () -> Primary) where Trailing == EmptyView {
        self.primary = primary()
        self.trailing = nil
    }

    init(@ViewBuilder primary: () -> Primary,
         @ViewBuilder trailing: () -> Trailing) {
        self.primary = primary()
        self.trailing = trailing()
    }

    var body: some View {
        GeometryReader { geo in
            // slot-i button centre = slotW·(i+0.5); pill edges = centre ∓ d/2.
            // Single: slot-1 leading edge → slot-4 trailing edge (3·slotW + d).
            // Pair: each slotW + d wide; gap = slotW − d (the inter-button gap).
            let slotW = geo.size.width / 4
            let d = CatchlightLayout.minTouchTarget
            HStack(spacing: slotW - d) {
                primary
                    .frame(width: trailing == nil ? slotW * 3 + d : slotW + d)
                if let trailing {
                    trailing
                        .frame(width: slotW + d)
                }
            }
            .padding(.leading, slotW / 2 - d / 2)
            .frame(height: d)
        }
        .frame(height: CatchlightLayout.minTouchTarget)
        .padding(.horizontal, CatchlightLayout.dockHorizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}
