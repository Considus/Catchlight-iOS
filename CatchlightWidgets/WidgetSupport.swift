//
//  WidgetSupport.swift
//  CatchlightWidgets — shared theme, provider, views (2026-06-23, restyled 2026-06-30)
//
//  All Catchlight widgets are LAUNCHERS: a single static entry, no timeline
//  refresh, no Take content. They render brand chrome and a deep link; tapping
//  opens the app to capture. Because nothing is decrypted or displayed, the
//  keychain wall is irrelevant here (owner 2026-06-22, Ideas Backlog §7).
//
//  Take and Obie widgets share these views, parameterised by `CaptureSurface`
//  (owner 2026-06-23: every Take widget has an Obie twin).
//
//  STYLING (owner 2026-06-30, widget brand pass): the extension can't link the
//  app's asset catalog / `CatchlightTheme` / `CatchlightGlyphs`, so the brand
//  tokens, fonts, and the Obie petal glyph are MIRRORED here (same hex / same
//  geometry). Two owner decisions drive this pass:
//   • Home-screen widgets are ADAPTIVE — they follow Night/Daylight like the app
//     (was a fixed cream that looked out of place on dark wallpapers).
//   • The home widget's Obie mark UNIFIES on the in-app petal glyph (ring + dot),
//     not `crown.fill`. Controls + lock-screen accessories stay `crown.fill`:
//     those surfaces are limited to SF Symbols, so they can't render the petal.
//

import WidgetKit
import SwiftUI
import CatchlightCore

// MARK: - Brand palette (mirrored from CatchlightTheme for the extension)
//
// The app's adaptive `Color.ck*` tokens live in the main target; the extension
// can't see them, so the values are mirrored here as dynamic UIColors with the
// SAME hex. Keep these in lock-step with CatchlightTheme's `Palette`.

/// 24-bit RGB hex → UIColor (the app's `init(hex:)` is private to its target, so
/// the extension carries its own copy — identical maths).
private extension UIColor {
    convenience init(rgbHex hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

enum WidgetPalette {
    /// Resolve to `dark` in Night, `light` in Daylight — mirrors `UIColor.adaptive`.
    private static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgbHex: dark) : UIColor(rgbHex: light)
        })
    }

    /// Screen / widget background — Ink (Night) / Paper (Daylight). `ckBackground`.
    static let background = adaptive(dark: 0x0F0E0C, light: 0xF7F4EF)
    /// Elevated surface (the medium card) — Dusk (Night) / White (Daylight). `ckSurface`.
    static let surface = adaptive(dark: 0x1C1A16, light: 0xFFFFFF)
    /// Primary text — Catchlight cream (Night) / Ink (Daylight). `ckTextPrimary`.
    static let textPrimary = adaptive(dark: 0xF5EDD8, light: 0x0F0E0C)
    /// Secondary / muted text — Fog (Night) / Slate (Daylight). `ckTextSecondary`.
    static let textSecondary = adaptive(dark: 0xB8B0A3, light: 0x5C5650)
    /// Obie-emphasis text — Glow (Night) / Ember Text (Daylight). `ckTextObie`.
    static let textObie = adaptive(dark: 0xEDD9A3, light: 0x856539)
    /// Amber accent for FOREGROUND glyphs/labels — Ember (Night) / Ember Text
    /// #856539 (Daylight, WCAG AA on Paper). `ckAccent`. Use for the "+" and ring.
    static let accent = adaptive(dark: 0xC9A96E, light: 0x856539)
    /// Brand gold as a FIXED fill (Control tint, card hairline) — Ember in both. `ckEmber`.
    static let ember = Color(uiColor: UIColor(rgbHex: 0xC9A96E))
}

// MARK: - Brand fonts (DM Sans, mirrored probe of CatchlightFont)
//
// The three brand TTFs are bundled into the extension (project.yml widget target
// + UIAppFonts). Variable TTFs only expose their default-instance PostScript name
// to UIFont, so — like `CatchlightFont` — we probe a candidate list and fall back
// to the system font. Widget chrome is all UI text → DM Sans (Take content is
// never the display face, DS §2.2 / D-042).

enum WidgetFont {
    private static let lightCandidates = ["DMSans-Light", "DMSans18pt-Light", "DMSans-9ptRegular", "DMSans-Regular", "DMSans"]
    private static let regularCandidates = ["DMSans-Regular", "DMSans18pt-Regular", "DMSans-9ptRegular", "DMSans"]
    private static let mediumCandidates = ["DMSans-Medium", "DMSans18pt-Medium", "DMSans-9ptRegular", "DMSans-Regular", "DMSans"]

    private static func firstAvailable(_ names: [String]) -> String? {
        names.first { UIFont(name: $0, size: 12) != nil }
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let candidates: [String]
        switch weight {
        case .light: candidates = lightCandidates
        case .medium, .semibold, .bold: candidates = mediumCandidates
        default: candidates = regularCandidates
        }
        if let name = firstAvailable(candidates) {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: weight)
    }
}

// MARK: - Capture surface (Take vs Obie presentation)

/// Describes what one launcher/card renders and where it routes. Both surfaces use
/// a Catchlight brand letter-mark (same italic-letter + catch-dot family): Take = the
/// Catchlight "C" icon, Obie = the Obie "O" glyph (owner 2026-06-30).
struct CaptureSurface {
    let url: URL
    let title: String        // "New Take" / "New Obie"
    let cardPrompt: String    // medium-card placeholder
    let isObie: Bool

    /// The brand letter-mark asset for this surface (`Assets.xcassets`). Used as a
    /// vector template image on the home + lock-screen surfaces.
    var glyphAsset: String { isObie ? WidgetAsset.obieGlyph : WidgetAsset.catchlightGlyph }
    /// Home-widget tint — each mark in its own brand colour (Obie gold / Catchlight
    /// primary). Lock-screen + Controls ignore this (system vibrant / tint).
    var glyphTint: Color { isObie ? WidgetPalette.textObie : WidgetPalette.textPrimary }

    static let take = CaptureSurface(
        url: CaptureRouting.captureURL(.text),
        title: "New Take",
        cardPrompt: "Tap to write a Take…",
        isObie: false
    )

    static let obie = CaptureSurface(
        url: CaptureRouting.captureURL(.obie),
        title: "New Obie",
        cardPrompt: "Tap to set your Obie…",
        isObie: true
    )
}

// MARK: - Brand letter-marks (the logo glyphs — `Assets.xcassets`)
//
// The Catchlight "C" and Obie "O" logos (italic letter + catch-dot), from
// 01_Brand/Logo/Custom Glyphs/{Catchlight,Obie}_Glyph.svg. Each is imported TWICE:
//   • a vector TEMPLATE IMAGE (`*Glyph`) for the home widgets + lock-screen
//     accessories (full SwiftUI — a solid silhouette survives the lock-screen
//     monochrome flattening, where the in-app petal could not);
//   • a custom SF SYMBOL (`*Symbol`) for the Controls — a Control's label takes an
//     SF Symbol, not a plain image asset (a plain image shows the "?" placeholder).
// (owner 2026-06-30 — Take + Obie read as a matched brand pair.)
enum WidgetAsset {
    static let obieGlyph = "ObieGlyph"
    static let catchlightGlyph = "CatchlightGlyph"
}

/// A brand letter-mark scaled to a target height. `tint` nil = no tint (lock-screen
/// accessories, where the system colours it); set it for the full-colour home widgets.
struct WidgetGlyphMark: View {
    let asset: String
    var height: CGFloat
    var tint: Color? = nil
    var body: some View {
        Image(asset)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .foregroundStyle(tint ?? Color.primary)
    }
}

// MARK: - Static launcher timeline

struct LauncherEntry: TimelineEntry {
    let date: Date
}

/// One fixed entry; launchers never need to refresh (`.never`).
struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry { LauncherEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
        completion(LauncherEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        completion(Timeline(entries: [LauncherEntry(date: Date())], policy: .never))
    }
}

// MARK: - Shared views

/// Home-small + lock-screen accessory launcher, parameterised by surface.
struct LauncherView: View {
    let surface: CaptureSurface
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            // Lock-screen accessory — system vibrant/monochrome; colour is ignored.
            // Both marks are solid silhouettes that survive the flattening.
            ZStack {
                AccessoryWidgetBackground()
                WidgetGlyphMark(asset: surface.glyphAsset, height: 30)
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                WidgetGlyphMark(asset: surface.glyphAsset, height: 24).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(surface.title).font(.headline)
                    Text("Catchlight").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
        default:
            // Home-screen small — full brand chrome, adaptive background.
            VStack(spacing: 12) {
                WidgetGlyphMark(asset: surface.glyphAsset, height: 52, tint: surface.glyphTint)
                Text(surface.title)
                    .font(WidgetFont.ui(15, weight: .medium))
                    .foregroundStyle(WidgetPalette.textPrimary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Medium "blank Take/Obie card" — styled as a Take row you tap to write into.
struct CardView: View {
    let surface: CaptureSurface

    var body: some View {
        HStack(spacing: 14) {
            WidgetGlyphMark(asset: surface.glyphAsset, height: 36, tint: surface.glyphTint)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(surface.cardPrompt)
                    .font(WidgetFont.ui(16))
                    .foregroundStyle(WidgetPalette.textSecondary)
                Text(surface.title)
                    .font(WidgetFont.ui(11, weight: .medium))
                    .foregroundStyle(WidgetPalette.accent)
                    .textCase(.uppercase)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WidgetPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(WidgetPalette.accent.opacity(0.18), lineWidth: 0.75)
                )
        )
    }
}
