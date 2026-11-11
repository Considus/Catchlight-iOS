//
//  DockPillRow.swift
//  Catchlight (iOS app target)
//
//  The bottom buttons of every screen that puts them in this row take the Dailies toolbar's place
//  and size (owner 2026-11-11: "make them all match the size
//  and shape of the new dailies menu"): in from each side by `dockInset`, up from the bottom
//  by the dock's gap, `dockHeight` tall, and corners that follow the screen's curve where
//  they reach the bottom edge (`CatchlightShape.edgeSurface`, never under the surface radius).
//  A single button spans the toolbar's width. A pair splits it in two with a gap between.
//

import SwiftUI

/// Whether a `DockPill` sits in a `DockPillRow`, at the screen's bottom edge, and so takes the
/// edge shape. A pill placed inline in a card keeps the plain control shape.
private struct DockAtScreenEdgeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    fileprivate var dockAtScreenEdge: Bool {
        get { self[DockAtScreenEdgeKey.self] }
        set { self[DockAtScreenEdgeKey.self] = newValue }
    }
}

/// The face of a `DockPill`: a rounded rectangle at the control radius, or in a `DockPillRow` the
/// edge shape that follows the screen's curve. Primary is the action colour with its on-colour
/// label, or the disabled pair while disabled. Secondary is the `outline` token as a 1pt edge
/// (3:1 on every surface) with primary text.
///
/// On the colour field the primary is the on-field colour with the field colour as its label.
/// The screens that sit on the field have no secondary button.
private struct DockPillFace: ViewModifier {
    let secondary: Bool
    @Environment(\.onColourField) private var onField
    @Environment(\.dockAtScreenEdge) private var atEdge
    @Environment(\.isEnabled) private var isEnabled
    func body(content: Content) -> some View {
        if atEdge {
            if onField && !secondary {
                content
                    .foregroundStyle(Color.ckField)
                    .flatEdgePanel(fill: Color.ckOnField, line: nil)
            } else if secondary {
                content
                    .foregroundStyle(Color.ckTextPrimary)
                    .flatEdgePanel(fill: .clear, line: Color.ckOutline)
            } else {
                content
                    .foregroundStyle(isEnabled ? Color.ckOnAccent : Color.ckDisabledLabel)
                    .flatEdgePanel(fill: isEnabled ? Color.ckAdd : Color.ckDisabledFill, line: nil)
            }
        } else if onField && !secondary {
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

/// One row at the dock's place. One child spans the toolbar's width; two children split it in two,
/// with a gap between them.
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

    // CTA growth (Default is the floor): above the default text size (.xLarge and up) the
    // toolbar's fixed height would force the CTA labels to shrink below their default size.
    // There the pills grow with their text instead, full width and stacked, never under 44pt,
    // at the same place, inset and shape. At the default size and below, each is `dockHeight` tall.
    @Environment(\.dynamicTypeSize) private var dynamicSize
    /// The home-indicator inset alone: the row stands where the Dailies toolbar does.
    @Environment(\.homeIndicatorInset) private var homeIndicatorInset
    /// The inset the keyboard or an input accessory adds on top of it, so a row shown with one up
    /// still rides above it. Zero when neither is showing.
    @Environment(\.deviceBottomInset) private var deviceBottomInset

    var body: some View {
        Group {
            if dynamicSize > .large {
                VStack(spacing: DailiesToolbarMetrics.chipGap) {
                    primary
                        .frame(maxWidth: .infinity, minHeight: CatchlightLayout.minTouchTarget)
                    if let trailing {
                        trailing
                            .frame(maxWidth: .infinity, minHeight: CatchlightLayout.minTouchTarget)
                    }
                }
            } else {
                HStack(spacing: DailiesToolbarMetrics.chipGap) {
                    primary
                        .frame(maxWidth: .infinity)
                    if let trailing {
                        trailing
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: CatchlightLayout.dockHeight)
            }
        }
        .environment(\.dockAtScreenEdge, true)
        .atDockPlace(homeIndicatorInset: homeIndicatorInset)
        .padding(.bottom, max(0, deviceBottomInset - homeIndicatorInset))
        // The fade behind the row starts this far above it, as the toolbar's does.
        .padding(.top, DailiesToolbarMetrics.fadeAbove)
    }
}
