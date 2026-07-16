//
//  CatchlightGlyphs.swift
//  Catchlight (iOS app target) — cosmetic baseline 2026-06-11
//
//  Custom meaning-led glyphs from the icon refinement pass (HiFi v1.6 §-wide):
//    • ImportantGlyph — an exclamation "!" (stem + dot): the app-wide Important mark
//                       (owner 2026-07-06; replaced the two-Iris glyph, matches the site).
//    • DailiesGlyph   — two Irises joined by the spine (the timeline motif). Currently
//                       unused — Important moved to ImportantGlyph — kept for reuse.
//    • SequenceGlyph  — three smaller beads chained on the spine: a SEQUENCE
//                       of Takes (sibling concept to Dailies).
//    • ObieGlyph      — the Obie brand logo (solid italic "O" + catch-dot), the
//                       Obie identity mark (matches the widget/brand glyph).
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

/// The Obie identity glyph — the Catchlight Obie brand logo (solid italic "O" +
/// catch-dot, `obie-glyph` asset from 01_Brand/Logo/Custom Glyphs/Obie_Glyph.svg).
/// Replaced the earlier ring-and-dot Mark glyph app-wide (owner 2026-06-30), so
/// the in-app Obie matches the widget/brand mark. Template image: tint via
/// `.foregroundStyle` (callers use `ckTextObie`). The glyph is taller than wide;
/// `scaledToFit` centres it in the `size` box.
struct ObieGlyph: View {
    var size: CGFloat = 16
    var body: some View {
        Image("obie-glyph")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// The checklist checkbox glyph (owner 2026-06-18): a SQUARE when open, a ticked CIRCLE when
/// complete. The caller wraps it in the 44pt touch target / Button.
///
/// ⚠️ KEEP IN STEP WITH `BlockEditorViewController.checkboxImage` — the editor is UIKit and draws
/// its own, so this pair can't be single-sourced the way `TakeCardStyle` is. Both must render the
/// SAME symbols at the SAME size: `square` / `checkmark.circle.fill`, 15pt regular,
/// `ckTextSecondary` / `ckAccent`. The open state drifted once already — the editor moved to the SF
/// `square` while this still hand-drew a `RoundedRectangle`, so a checklist item looked different in
/// the Shot List than in the Take you'd just typed it into (owner 2026-07-16). This view was
/// originally shared with the SwiftUI inline editor, which is what kept them honest; that editor
/// died at M7, so the only thing holding them together now is this comment.
struct TaskCheckbox: View {
    let isComplete: Bool
    /// 15pt, matching the editor's `SymbolConfiguration(pointSize: 15, weight: .regular)`.
    /// The caller still wraps it in the 44pt touch frame, so the tap target is unchanged.
    var size: CGFloat = 15
    var body: some View {
        Image(systemName: isComplete ? "checkmark.circle.fill" : "square")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(isComplete ? Color.ckAccent : Color.ckTextSecondary)
    }
}

/// The Important mark — an exclamation "!" (owner 2026-07-06, outline form 2026-07-06).
/// Replaces the two-Iris `DailiesGlyph` as the app-wide Important glyph, matching the
/// redesigned marketing site where Important is a "!". Drawn as a STROKED OUTLINE — a
/// tapered stem (rounded top corners, narrowing to a rounded foot) above a ring dot — at
/// the house `1.2`-unit weight with round caps/joins, so it sits beside the other line
/// glyphs (Dailies/Sequence) and the .light SF Symbols, and colours via `.foregroundStyle`.
struct ImportantGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let u = min(rect.width, rect.height) / 16
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }
        var p = Path()
        // Tapered stem — rounded top corners, tapering sides, rounded foot.
        p.move(to: pt(6.0, 2.45))
        p.addQuadCurve(to: pt(6.85, 1.6), control: pt(6.0, 1.6))
        p.addLine(to: pt(9.15, 1.6))
        p.addQuadCurve(to: pt(10.0, 2.45), control: pt(10.0, 1.6))
        p.addLine(to: pt(8.95, 10.45))
        p.addQuadCurve(to: pt(8.0, 11.4), control: pt(8.85, 11.4))
        p.addQuadCurve(to: pt(7.05, 10.45), control: pt(7.15, 11.4))
        p.closeSubpath()
        // Dot — a ring, matching the stroke weight.
        p.addEllipse(in: CGRect(x: (8 - 1.15) * u, y: (13.85 - 1.15) * u, width: 2.3 * u, height: 2.3 * u))
        return p
    }
}

struct ImportantGlyph: View {
    var size: CGFloat = 20
    var body: some View {
        ImportantGlyphShape()
            .stroke(style: StrokeStyle(lineWidth: size * 1.2 / 16, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

/// `ImportantGlyph` with a diagonal strike — the "Remove Important" counterpart. Same
/// direction and weight as the app's other `.slash` marks, so it reads as the Important
/// "!" crossed out.
struct ImportantGlyphSlashed: View {
    var size: CGFloat = 20
    var body: some View {
        let lw = size * 1.5 / 16
        ImportantGlyph(size: size)
            .overlay {
                Path { p in
                    // bottom-left → top-right, matching the SF `.slash` direction
                    p.move(to: CGPoint(x: size * 0.12, y: size * 0.88))
                    p.addLine(to: CGPoint(x: size * 0.88, y: size * 0.12))
                }
                .stroke(style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }
            .frame(width: size, height: size)
    }
}

// MARK: - Baked menu glyphs

/// System context menus (`UIMenu`) render only `Image`s, never SwiftUI `Shape`s, so
/// our custom glyphs are baked ONCE into template `UIImage`s that the menu tints like
/// any SF Symbol. Lets the Take long-press menu show the *standard* Important / Obie
/// marks instead of stand-in symbols (`star` / `pin`) — owner 2026-06-29.
/// `@MainActor` (ImageRenderer is main-actor) + cached (the glyphs never change).
@MainActor
enum MenuGlyph {
    static let makeImportant = bake(ImportantGlyph(size: glyphSize))
    static let removeImportant = bake(ImportantGlyphSlashed(size: glyphSize))
    // The solid brand "O" reads heavier than the line glyphs, so it's rendered a
    // touch smaller *within* the shared `glyphSize` slot (so it still aligns) — the
    // SAME 26→22 (≈0.85×) reduction applied to the focus-ring-fan Obie Mark (owner 2026-07-01).
    static let obie = bake(ObieGlyph(size: glyphSize * 22 / 26))

    /// Rendered a touch larger than the dock glyphs — menu icons read small.
    private static let glyphSize: CGFloat = 22

    private static func bake<V: View>(_ glyph: V) -> Image {
        // Foreground black + template rendering: the menu ignores RGB and tints by
        // alpha, exactly as it does for SF Symbols, so the glyph picks up the menu's
        // own label colour (and red for destructive rows).
        let renderer = ImageRenderer(
            content: glyph
                .foregroundStyle(.black)
                .frame(width: glyphSize, height: glyphSize)
                .padding(2)
        )
        renderer.scale = 3
        if let ui = renderer.uiImage?.withRenderingMode(.alwaysTemplate) {
            return Image(uiImage: ui)
        }
        return Image(systemName: "star")   // defensive fallback; should never hit
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
        ImportantGlyph().foregroundStyle(Color.ckEmber)
        ImportantGlyphSlashed().foregroundStyle(Color.ckEmber)
        DailiesGlyph().foregroundStyle(Color.ckEmber)
        SequenceGlyph().foregroundStyle(Color.ckEmber)
        ObieGlyph().foregroundStyle(Color.ckTextObie)
    }
    .padding()
    .background(Color.ckBackground)
}
