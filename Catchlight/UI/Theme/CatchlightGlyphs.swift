//
//  CatchlightGlyphs.swift
//  Catchlight (iOS app target) — cosmetic baseline 2026-06-11
//
//  Custom meaning-led glyphs from the icon refinement pass (HiFi v1.6 §-wide):
//    • DailiesGlyph   — two Irises joined by the spine: the timeline itself.
//    • SequenceGlyph  — three smaller beads chained on the spine: a SEQUENCE
//                       of Takes (sibling concept to Dailies).
//    • ObiePetalGlyph — compact ring + specular dot, the Obie identity at the
//                       same optical size as the other petal icons.
//  All drawn on the prototype's 16-unit grid with light ~1.2-unit strokes so
//  they sit beside SF Symbols rendered at .light weight.
//

import SwiftUI

/// Two Irises on the spine (Dailies). Stroke-only; colour via .foregroundStyle.
struct DailiesGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let u = min(rect.width, rect.height) / 16
        var p = Path()
        p.addEllipse(in: CGRect(x: (8 - 2.3) * u, y: (4.3 - 2.3) * u, width: 4.6 * u, height: 4.6 * u))
        p.move(to: CGPoint(x: 8 * u, y: 6.9 * u))
        p.addLine(to: CGPoint(x: 8 * u, y: 9.1 * u))
        p.addEllipse(in: CGRect(x: (8 - 2.3) * u, y: (11.7 - 2.3) * u, width: 4.6 * u, height: 4.6 * u))
        return p
    }
}

/// Three beads chained on the spine (Sequence).
struct SequenceGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let u = min(rect.width, rect.height) / 16
        var p = Path()
        for (cy, link) in [(2.9, true), (8.0, true), (13.1, false)] {
            p.addEllipse(in: CGRect(x: (8 - 1.8) * u, y: (cy - 1.8) * u, width: 3.6 * u, height: 3.6 * u))
            if link {
                p.move(to: CGPoint(x: 8 * u, y: (cy + 1.8) * u))
                p.addLine(to: CGPoint(x: 8 * u, y: (cy + 3.3) * u))
            }
        }
        return p
    }
}

/// Convenience views matching the dock's SF Symbol sizing (icon box ~20pt).
struct DailiesGlyph: View {
    var size: CGFloat = 20
    var body: some View {
        DailiesGlyphShape()
            .stroke(style: StrokeStyle(lineWidth: size * 1.2 / 16, lineCap: .round))
            .frame(width: size, height: size)
    }
}

struct SequenceGlyph: View {
    var size: CGFloat = 20
    var body: some View {
        SequenceGlyphShape()
            .stroke(style: StrokeStyle(lineWidth: size * 1.2 / 16, lineCap: .round))
            .frame(width: size, height: size)
    }
}

/// The Obie petal glyph — ring + specular dot with a background-coloured catch.
/// Drawn in `ckTextObie` by the petal (readable warm identity, not raw Ember).
struct ObiePetalGlyph: View {
    var size: CGFloat = 16
    var body: some View {
        let u = size / 16
        ZStack {
            Circle()
                .strokeBorder(lineWidth: 1.3 * u)
                .frame(width: 10.8 * u, height: 10.8 * u)
            Circle()
                .frame(width: 3.4 * u, height: 3.4 * u)
                .overlay(
                    Circle()
                        .fill(Color.ckBackground)
                        .frame(width: 1.4 * u, height: 1.4 * u)
                )
                .offset(x: 3.9 * u, y: -3.9 * u)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Device metrics environment

/// The window's top safe-area inset, captured ONCE at the window root in
/// CatchlightApp (a GeometryReader OUTSIDE `.ignoresSafeArea(.container)`)
/// and passed down here. The app runs full-bleed, so SwiftUI's own safe-area
/// plumbing reports zero inside — and reading `UIApplication...keyWindow`
/// in a view body is a hard NO (keyboard window becomes key → layout thrash;
/// a `static let` UIKit read traps in dispatch_once recursion — both
/// root-caused 2026-06-11).
private struct DeviceTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 59
}

/// The window's BOTTOM safe-area inset (home-indicator zone), captured ONCE at
/// the window root in CatchlightApp from the SAME GeometryReader as
/// `deviceTopInset` (the app runs full-bleed via `.ignoresSafeArea(.container)`,
/// so SwiftUI's own safe-area plumbing reports zero inside). Read by the bottom
/// dock and the onboarding/paywall pill row so they rest ABOVE the home
/// indicator rather than inside it (section 4 / D-041). Default ~34 matches the
/// home-indicator inset on a notched/Dynamic-Island device so previews and any
/// pre-capture frame are sensible.
private struct DeviceBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 34
}

extension EnvironmentValues {
    var deviceTopInset: CGFloat {
        get { self[DeviceTopInsetKey.self] }
        set { self[DeviceTopInsetKey.self] = newValue }
    }

    var deviceBottomInset: CGFloat {
        get { self[DeviceBottomInsetKey.self] }
        set { self[DeviceBottomInsetKey.self] = newValue }
    }
}

#Preview("Glyphs") {
    HStack(spacing: 24) {
        DailiesGlyph().foregroundStyle(Color.ckEmber)
        SequenceGlyph().foregroundStyle(Color.ckEmber)
        ObiePetalGlyph().foregroundStyle(Color.ckTextObie)
    }
    .padding()
    .background(Color.ckBackground)
}
