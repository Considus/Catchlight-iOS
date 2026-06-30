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

/// Describes what one launcher/card renders and where it routes. Take uses the
/// ember-outline "+" ring (the in-app Add button); Obie uses the petal identity
/// mark on the home widget, `crown.fill` on the SF-Symbol-only surfaces.
struct CaptureSurface {
    let url: URL
    let title: String        // "New Take" / "New Obie"
    let cardPrompt: String    // medium-card placeholder
    let accessoryGlyph: String // SF Symbol for the lock-screen / accessory mark
    let isObie: Bool

    static let take = CaptureSurface(
        url: CaptureRouting.captureURL(.text),
        title: "New Take",
        cardPrompt: "Tap to write a Take…",
        accessoryGlyph: "plus.circle.fill",
        isObie: false
    )

    static let obie = CaptureSurface(
        url: CaptureRouting.captureURL(.obie),
        title: "New Obie",
        cardPrompt: "Tap to set your Obie…",
        accessoryGlyph: "crown.fill",
        isObie: true
    )
}

// MARK: - Obie brand glyph (the logo mark — `Assets.xcassets/ObieGlyph`)
//
// The Catchlight Obie logo: a SOLID filled italic "O" + filled dot (from
// 01_Brand/Logo/Custom Glyphs/Obie_Glyph.svg), imported as a vector template
// asset. Used on EVERY widget surface (owner 2026-06-30) — home widgets, the
// lock-screen accessories, AND the Controls. A solid silhouette survives the
// lock-screen / Control monochrome (vibrant) flattening, where the in-app petal
// (a thin ring + background-punched catch) could not. Home tints it `ckTextObie`;
// lock-screen + Controls let the system tint it.
//
// The asset name shared with the Controls.
enum WidgetAsset { static let obieGlyph = "ObieGlyph" }

/// The Obie brand mark, scaled to a target height and gold-tinted (home widgets).
struct WidgetObieMark: View {
    var height: CGFloat
    var tinted: Bool = true
    var body: some View {
        Image(WidgetAsset.obieGlyph)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .foregroundStyle(tinted ? WidgetPalette.textObie : Color.primary)
    }
}

/// The Take "+" mark — the in-app Add button (dock-button spec: accent ring @0.55,
/// `plus` at `.regular`, accent glyph). `diameter` lets the small widget and the
/// medium card share one definition at two sizes.
struct WidgetAddMark: View {
    var diameter: CGFloat = 52
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(WidgetPalette.accent.opacity(0.55), lineWidth: diameter * 1.5 / 44)
                .frame(width: diameter, height: diameter)
            Image(systemName: "plus")
                .font(.system(size: diameter * 24 / 44, weight: .regular))
                .foregroundStyle(WidgetPalette.accent)
        }
        .frame(width: diameter, height: diameter)
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
            // Take = plus.circle.fill (SF Symbol); Obie = the brand glyph (solid
            // silhouette, survives the monochrome flattening — owner 2026-06-30).
            ZStack {
                AccessoryWidgetBackground()
                if surface.isObie {
                    WidgetObieMark(height: 30, tinted: false)
                } else {
                    Image(systemName: surface.accessoryGlyph)
                        .font(.system(size: 24, weight: .semibold))
                }
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                if surface.isObie {
                    WidgetObieMark(height: 24, tinted: false).frame(width: 22)
                } else {
                    Image(systemName: surface.accessoryGlyph)
                        .font(.system(size: 22, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(surface.title).font(.headline)
                    Text("Catchlight").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
        default:
            // Home-screen small — full brand chrome, adaptive background.
            VStack(spacing: 12) {
                if surface.isObie {
                    // Match the Add mark's footprint so the Take/Obie widgets balance.
                    WidgetObieMark(height: 52)
                } else {
                    WidgetAddMark(diameter: 56)
                }
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
            if surface.isObie {
                WidgetObieMark(height: 36)
                    .frame(width: 40, height: 40)
            } else {
                WidgetAddMark(diameter: 40)
            }

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
