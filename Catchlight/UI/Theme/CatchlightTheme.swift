//
//  CatchlightTheme.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  The single source of truth for colour and typography. NO view in the UI layer
//  may hard-code a colour or a font size; everything routes through here so that:
//
//    • Night / Daylight switch automatically. Semantic colours are built from
//      `UIColor` dynamic providers, so a single `Color` value resolves to the
//      correct Night (dark) or Daylight (light) variant via the active
//      `userInterfaceStyle`. Views still read `@Environment(\.colorScheme)` where
//      they need to branch logic (e.g. petal styling), but the colours themselves
//      are adaptive by construction.
//    • Dynamic Type is respected. Font helpers use `relativeTo:` so custom fonts
//      scale, and the system fallbacks scale automatically.
//
//  Night mode is the design default; Daylight is the light-appearance counterpart.
//

import SwiftUI

// MARK: - Hex helpers

extension Color {
    /// Build a Color from a 24-bit RGB hex (e.g. 0xF5EDD8).
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }

    /// A dynamic colour that resolves to `dark` in Night mode and `light` in Daylight.
    static func adaptive(dark: UIColor, light: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }
}

// MARK: - Raw palette (the named brand swatches)

extension Color {
    // Night-mode (dark) palette — the brand's core.
    static let ckInk = Color(hex: 0x0F0E0C)
    static let ckDusk = Color(hex: 0x1C1A16)
    static let ckCatchlight = Color(hex: 0xF5EDD8)   // "catchlightCream"
    static let ckGlow = Color(hex: 0xEDD9A3)
    static let ckEmber = Color(hex: 0xC9A96E)
    static let ckFog = Color(hex: 0xB8B0A3)
    static let ckShadow = Color(hex: 0x0A0908)

    // Daylight-only swatches.
    static let ckPaper = Color(hex: 0xF7F4EF)
    static let ckObieDaylight = Color(hex: 0xA07840)
    // "Stone" is the Daylight petal fill. The brief names it without a hex, so this
    // is a deliberate, documented choice: a warm light stone that reads as a filled
    // chip against Paper. TODO: confirm exact Stone hex with design before release.
    static let ckStone = Color(hex: 0xE7E1D5)
}

// MARK: - Raw UIColors (for dynamic providers)

private enum Palette {
    static let ink = UIColor(hex: 0x0F0E0C)
    static let dusk = UIColor(hex: 0x1C1A16)
    static let catchlight = UIColor(hex: 0xF5EDD8)
    static let glow = UIColor(hex: 0xEDD9A3)
    static let ember = UIColor(hex: 0xC9A96E)
    static let fog = UIColor(hex: 0xB8B0A3)
    static let shadow = UIColor(hex: 0x0A0908)
    static let paper = UIColor(hex: 0xF7F4EF)
    static let white = UIColor.white
    static let obieDaylight = UIColor(hex: 0xA07840)
    static let stone = UIColor(hex: 0xE7E1D5)
}

// MARK: - Semantic, adaptive colours (Night / Daylight)
//
// These are the ONLY colours views should reference for surfaces, text, and chrome.

extension Color {
    /// Screen background — Ink (Night) / Paper (Daylight).
    static let ckBackground = Color(uiColor: .adaptive(dark: Palette.ink, light: Palette.paper))

    /// Elevated surface (cards, edit sheet) — Dusk (Night) / White (Daylight).
    static let ckSurface = Color(uiColor: .adaptive(dark: Palette.dusk, light: Palette.white))

    /// Primary text — Catchlight cream (Night) / Ink (Daylight).
    static let ckTextPrimary = Color(uiColor: .adaptive(dark: Palette.catchlight, light: Palette.ink))

    /// Obie-emphasis text — Glow (Night) / #A07840 (Daylight).
    static let ckTextObie = Color(uiColor: .adaptive(dark: Palette.glow, light: Palette.obieDaylight))

    /// Secondary / muted text — Fog (both modes).
    static let ckTextSecondary = Color(uiColor: .adaptive(dark: Palette.fog, light: Palette.fog))

    /// The timeline spine — Catchlight @ 18% (Night) / Ink @ 13% (Daylight).
    static let ckSpine = Color(uiColor: .adaptive(
        dark: Palette.catchlight.withAlphaComponent(0.18),
        light: Palette.ink.withAlphaComponent(0.13)
    ))

    /// The Add button — Ember (both).
    static let ckAdd = Color(uiColor: .adaptive(dark: Palette.ember, light: Palette.ember))

    /// Active navigation icon — Ember (both).
    static let ckNavActive = Color(uiColor: .adaptive(dark: Palette.ember, light: Palette.ember))

    /// Inactive navigation icon — Catchlight @ 55% (Night) / Fog (Daylight).
    static let ckNavInactive = Color(uiColor: .adaptive(
        dark: Palette.catchlight.withAlphaComponent(0.55),
        light: Palette.fog
    ))

    /// Dim overlay behind fans/sheets — Ink @ 80% (Night) / Paper @ 88% (Daylight).
    static let ckDim = Color(uiColor: .adaptive(
        dark: Palette.ink.withAlphaComponent(0.80),
        light: Palette.paper.withAlphaComponent(0.88)
    ))
}

// MARK: - Quadrant / petal fills (mode-dependent — resolved by the caller)
//
// These need the active colour scheme because the same activity reads differently
// per mode. Views pass their `@Environment(\.colorScheme)` in.

enum Quadrant {
    /// Top-right: Note — Catchlight @ 50% (Night) / Ink @ 30% (Daylight).
    static func note(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.ckCatchlight.opacity(0.50) : Color.ckInk.opacity(0.30)
    }

    /// Bottom-right: Reminder — Ember (both).
    static func reminder(_ scheme: ColorScheme) -> Color { .ckEmber }

    /// Bottom-left: Task — Glow @ 60% (Night) / Ink @ 12% (Daylight).
    static func task(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.ckGlow.opacity(0.60) : Color.ckInk.opacity(0.12)
    }

    /// Obie ring around the whole circle — Glow (Night) / Ember (Daylight).
    static func obieRing(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .ckGlow : .ckEmber
    }
}

// MARK: - Typography

enum CatchlightFont {
    // TODO: BEFORE RELEASE — bundle these fonts as app resources and register them in
    // Info.plist (UIAppFonts). Until then `isAvailable` is false and the helpers fall
    // back to system serif / system sans, which keeps the UI legible in development.
    static let displayName = "CormorantGaramond-LightItalic"
    static let uiLightName = "DMSans-Light"
    static let uiRegularName = "DMSans-Regular"
    static let uiMediumName = "DMSans-Medium"

    private static func isAvailable(_ name: String) -> Bool {
        UIFont(name: name, size: 12) != nil
    }

    /// Display / Take text — Cormorant Garamond Light Italic, scaling with Dynamic
    /// Type. Falls back to the system serif (italic) when the font is not bundled.
    static func display(size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        if isAvailable(displayName) {
            return .custom(displayName, size: size, relativeTo: style)
        }
        return .system(style, design: .serif).italic()
    }

    /// Interface text — DM Sans, scaling with Dynamic Type. Falls back to the
    /// system sans (rounded-neutral) when the font is not bundled.
    static func ui(_ weight: Font.Weight = .regular,
                   size: CGFloat,
                   relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String
        switch weight {
        case .light: name = uiLightName
        case .medium, .semibold, .bold: name = uiMediumName
        default: name = uiRegularName
        }
        if isAvailable(name) {
            return .custom(name, size: size, relativeTo: style)
        }
        return .system(style, design: .default).weight(weight)
    }
}

// MARK: - Layout constants

enum CatchlightLayout {
    /// Diameter of a Take circle on the timeline.
    static let circleDiameter: CGFloat = 22
    /// Width of the timeline spine.
    static let spineWidth: CGFloat = 2
    /// Leading inset from screen edge to the circle's centre (so the spine has room).
    static let spineLeading: CGFloat = 32
    /// Minimum touch target per HIG / accessibility.
    static let minTouchTarget: CGFloat = 44
    /// Standard dim-overlay opacity is baked into Color.ckDim.
}
