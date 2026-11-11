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
//  The grid is the same one DailiesToolbar and CatchlightLayout.addColumnX derive
//  from: four equal slots inside `toolbarHorizontalPadding`, button diameter
//  `minTouchTarget` — so the pills inherit the 44pt HIG touch target and the
//  row occupies the dock's exact resting position (top 10 / bottom 8 padding).
//

import SwiftUI

/// The face of a `DockPill`: a rounded rectangle at the control radius. Primary is the action
/// colour with its on-colour label, or the disabled pair while disabled. Secondary is the
/// `outline` token as a 1pt edge (3:1 on every surface) with primary text.
///
/// On the colour field the primary is the on-field colour with the field colour as its label.
/// The screens that sit on the field have no secondary button.
private struct DockPillFace: ViewModifier {
    let secondary: Bool
    @Environment(\.onColourField) private var onField
    func body(content: Content) -> some View {
        if onField && !secondary {
            content
                .foregroundStyle(Color.ckField)
                .background(CatchlightShape.control.fill(Color.ckOnField))
                .contentShape(CatchlightShape.control)
        } else if secondary {
            content
                .foregroundStyle(Color.ckTextPrimary)
                .background(CatchlightShape.control.strokeBorder(Color.ckOutline, lineWidth: 1))
                .contentShape(CatchlightShape.control)
        } else {
            content.flatPrimaryFace()
        }
    }
}

/// The standard dock-geometry button label: a rounded rectangle at the control radius.
/// Primary is the action colour with its on-colour label (secondary: an outline).
struct DockPill: View {
    let title: LocalizedStringKey
    var secondary: Bool = false
    let action: () -> Void

    // CTA growth (Default is the floor): at any size ABOVE the
    // default (.xLarge and up, through AX5) the CTA label may wrap to two lines
    // and grows instead of shrinking, defining the pill height itself (≥44pt) —
    // so the label is never rendered smaller than at the default size. At the
    // default size and below, the locked dock geometry is unchanged: one line,
    // shrink-to-fit, filling the parent's fixed 44pt row.
    @Environment(\.dynamicTypeSize) private var dynamicSize

    var body: some View {
        Button(action: action) {
            Text(title)
                .ckBody(.medium, size: 15, relativeTo: .body)
                .lineLimit(dynamicSize > .large ? 2 : 1)
                .minimumScaleFactor(dynamicSize > .large ? 1.0 : 0.75)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity,
                       minHeight: dynamicSize > .large ? CatchlightLayout.minTouchTarget : nil,
                       maxHeight: dynamicSize > .large ? nil : .infinity)
                .modifier(DockPillFace(secondary: secondary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// The one fade scrolling content goes into at a screen edge: under the bottom toolbar and
/// pill rows, and under the pinned Obie at the top (owner 2026-11-11: both edges alike). Clear
/// at the open side, 85% page colour at 28% of the way, solid from 55%.
enum EdgeFade {
    /// `solid` is the side the content goes under.
    /// `ground` is the colour the content fades into: the page's ground, or the colour field on
    /// the screens that sit on it.
    static func gradient(solid: VerticalEdge, ground: Color = .ckBackground) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: ground.opacity(0), location: 0),
            .init(color: ground.opacity(0.85), location: 0.28),
            .init(color: ground, location: 0.55)
        ], startPoint: solid == .bottom ? .top : .bottom, endPoint: solid == .bottom ? .bottom : .top)
    }
}

extension View {
    /// The dock's soft bottom edge behind a pill row (HiFi v1.11.5, owner
    /// 2026-06-12): scrolling content fades out beneath the button zone
    /// instead of meeting a hard edge. Apply to the safeAreaInset content.
    /// `passesTouches`: the fade is only a look, so content still showing through it keeps its
    /// taps (the Dailies toolbar, whose fade reaches above the panel over the Takes).
    func dockFadeBackground(passesTouches: Bool = false) -> some View {
        modifier(DockFade(passesTouches: passesTouches))
    }
}

/// The fade itself, into the page's ground or into the colour field on the screens that sit on it.
private struct DockFade: ViewModifier {
    let passesTouches: Bool
    @Environment(\.onColourField) private var onField
    func body(content: Content) -> some View {
        content.background(
            EdgeFade.gradient(solid: .bottom, ground: onField ? .ckField : .ckBackground)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(!passesTouches)
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

    // CTA growth (Default is the floor): above the default text
    // size (.xLarge and up) the locked dock-slot grid (fixed 44pt height,
    // slot-aligned widths) would force the CTA labels to shrink below their
    // default size. Abandon exact dock alignment there and let the pills grow
    // full-width instead. At the default size and below, the grid is unchanged.
    @Environment(\.dynamicTypeSize) private var dynamicSize
    /// Bottom safe-area inset. The onboarding/paywall pill
    /// row mirrors the resting dock's geometry, so it must lift by the same
    /// home-indicator inset to line up with the dock at rest.
    @Environment(\.deviceBottomInset) private var deviceBottomInset

    var body: some View {
        if dynamicSize > .large {
            // Full-width layout: a single primary pill spans the width; a primary
            // plus a trailing pill stack vertically, each full width and ≥44pt.
            VStack(spacing: 10) {
                primary
                    .frame(maxWidth: .infinity, minHeight: CatchlightLayout.minTouchTarget)
                if let trailing {
                    trailing
                        .frame(maxWidth: .infinity, minHeight: CatchlightLayout.minTouchTarget)
                }
            }
            .padding(.horizontal, CatchlightLayout.toolbarHorizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, deviceBottomInset + 8)
        } else {
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
            .padding(.horizontal, CatchlightLayout.toolbarHorizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, deviceBottomInset + 8)
        }
    }
}
