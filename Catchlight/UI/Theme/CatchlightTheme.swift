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
    /// Accessible amber for text on Paper — WCAG AA (4.5:1+). Matches website `--ember-text`.
    static let ckEmberText = Color(hex: 0x856539)
    /// Accessible warm-grey for secondary text on Paper — WCAG AA. Replaces Fog in Daylight.
    static let ckSlate = Color(hex: 0x5C5650)
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
    /// Accessible secondary text on Paper — WCAG AA. Replaces fog in Daylight (fog fails on Paper at body size).
    static let slate = UIColor(hex: 0x5C5650)
    /// Accessible amber text on Paper — WCAG AA. Matches website `--ember-text: #856539`.
    static let emberText = UIColor(hex: 0x856539)
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

    /// Obie-emphasis text — Glow (Night) / Ember Text #856539 (Daylight, WCAG AA on Paper).
    static let ckTextObie = Color(uiColor: .adaptive(dark: Palette.glow, light: Palette.emberText))

    /// Secondary / muted text — Fog (Night) / Slate #5C5650 (Daylight, WCAG AA on Paper).
    /// Fog (#B8B0A3) fails WCAG AA for body text on Paper; Slate is the accessible replacement.
    static let ckTextSecondary = Color(uiColor: .adaptive(dark: Palette.fog, light: Palette.slate))

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

    /// Amber accent for FOREGROUND content (text or iconography) drawn on a
    /// background SURFACE — Ember (Night) / Ember Text #856539 (Daylight).
    /// Use this — NOT raw `ckEmber` — for any amber glyph or label sitting on
    /// `ckBackground` / `ckSurface`: dock icons, settings-row icons, timeline
    /// banner action labels. Raw Ember (#C9A96E) on Paper is only ~2:1 and
    /// fails both WCAG AA text (4.5:1) and UI-component (3:1) contrast; #856539
    /// gives 4.9:1 on Paper and 5.4:1 on white. Night is UNCHANGED (resolves to
    /// Ember). Raw `ckEmber` / `ckAdd` remain the FILL colour (Add droplet,
    /// selection borders, pill fills), where Ember is correct.
    /// (Accessibility audit 7.6 / D-027 follow-up 2026-06-13.)
    static let ckAccent = Color(uiColor: .adaptive(dark: Palette.ember, light: Palette.emberText))

    /// Foreground drawn ON an Ember fill (the Add "+", active filter glyphs):
    /// Ink in BOTH modes. Night was already Ink-coloured (it used `ckBackground`
    /// = Ink), so this is unchanged there; in Daylight it replaces Paper-on-Ember
    /// (2.04:1, fails) with Ink-on-Ember (8.62:1). Use for amber-filled chrome
    /// controls. NOTE: the locked D-022 primary CTAs (DockPill, Paywall) are a
    /// separate owner call (see audit C4) and are NOT switched here.
    static let ckOnAccent = Color(uiColor: .adaptive(dark: Palette.ink, light: Palette.ink))

    /// The veil — the ONE obscuring overlay for the Dial, the editor, and the
    /// Settings backdrop (owner decision 2026-06-11: solid 90% background veil
    /// everywhere; no blur, no dark tint in Daylight). Ink @ 90% (Night) /
    /// Paper @ 90% (Daylight). The screens beneath stay full-opacity — the
    /// veil alone provides the recede.
    static let ckDim = Color(uiColor: .adaptive(
        dark: Palette.ink.withAlphaComponent(0.90),
        light: Palette.paper.withAlphaComponent(0.90)
    ))

    /// Error / warning accent — used by the non-blocking error strips on the
    /// timeline (Task 3.9). Same hue in both modes so the strip reads as an
    /// alert regardless of theme; brightness chosen to remain WCAG AA against
    /// `ckTextPrimary`. Strips themselves use this colour at ~12–15% opacity.
    static let ckRuby = Color(uiColor: .adaptive(
        dark: UIColor(red: 0.86, green: 0.32, blue: 0.32, alpha: 1.0),
        light: UIColor(red: 0.72, green: 0.18, blue: 0.18, alpha: 1.0)
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

// MARK: - Daylight card shadow (Design System v1.1 §4.1)

/// The standard Take-card shadow for ckSurface cards/chips on Paper: ambient
/// `0 2px 8px rgba(15,14,12,0.09)` + contact `0 1px 2px rgba(15,14,12,0.05)`.
/// Daylight ONLY — DS §4 prohibits shadows in Night, where elevation is the
/// Dusk surface colour. CSS blur ≈ 2× SwiftUI radius, hence radius 4/1.
struct DaylightCardShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .shadow(color: scheme == .dark ? .clear : Color.ckInk.opacity(0.09),
                    radius: 4, y: 2)
            .shadow(color: scheme == .dark ? .clear : Color.ckInk.opacity(0.05),
                    radius: 1, y: 1)
    }
}

extension View {
    func daylightCardShadow() -> some View { modifier(DaylightCardShadow()) }
}

// MARK: - Typography

enum CatchlightFont {
    // Cormorant Garamond and DM Sans are bundled as variable TTFs under
    // `Catchlight/Resources/Fonts/` and registered in `Info.plist` (UIAppFonts).
    // Variable TTFs expose only their *default* instance's PostScript name to
    // UIFont; the per-weight names (e.g. "DMSans-Light") don't resolve. We probe
    // a candidate list per weight and use the first that registers — defence in
    // depth against minor PostScript-name drift across font releases.

    // Actual PostScript names (probed from bundled variable TTFs via name table ID 6):
    //   CormorantGaramond-Italic[wght].ttf  → CormorantGaramond-LightItalic
    //   CormorantGaramond[wght].ttf         → CormorantGaramond-Light
    //   DMSans[opsz,wght].ttf               → DMSans-9ptRegular (default instance;
    //                                          variable font also registers named
    //                                          instances such as DMSans-Regular)
    private static let displayCandidates = [
        "CormorantGaramond-LightItalic",   // confirmed PS name — matches first
        "CormorantGaramond-Italic",
        "CormorantGaramond-Light",
        "CormorantGaramond"
    ]
    private static let uiLightCandidates = [
        "DMSans-Light", "DMSans18pt-Light", "DMSans-9ptRegular", "DMSans-Regular", "DMSans"
    ]
    private static let uiRegularCandidates = [
        "DMSans-Regular", "DMSans18pt-Regular", "DMSans-9ptRegular", "DMSans"
    ]
    private static let uiMediumCandidates = [
        "DMSans-Medium", "DMSans18pt-Medium", "DMSans-9ptRegular", "DMSans-Regular", "DMSans"
    ]

    /// Resolution cache — `firstAvailable` is called for every `Text` on every
    /// render, and `UIFont(name:)` probing is not free. The installed font set
    /// cannot change mid-process, so the first resolution is authoritative.
    private static var resolvedNames: [String: String?] = [:]
    private static let resolveLock = NSLock()

    private static func firstAvailable(_ names: [String]) -> String? {
        let key = names.joined(separator: "|")
        resolveLock.lock()
        defer { resolveLock.unlock() }
        if let cached = resolvedNames[key] { return cached }
        let resolved = names.first { UIFont(name: $0, size: 12) != nil }
        resolvedNames[key] = resolved
        return resolved
    }

    /// Display / Take text — Cormorant Garamond Italic, scaling with Dynamic
    /// Type. Falls back to the system serif (italic) when the font is not bundled.
    /// Use for USER CONTENT rendered in the display face (e.g. Take body text on
    /// rows / edit sheet) — content must respect the user's text size preference.
    static func display(size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        if let name = firstAvailable(displayCandidates) {
            return .custom(name, size: size, relativeTo: style)
        }
        return .system(style, design: .serif).italic()
    }

    /// Display / brand headings — Cormorant Garamond Italic at a FIXED point size
    /// that does NOT respond to Dynamic Type. Use ONLY for brand display: the
    /// wordmark, onboarding headings, the Obie title treatment, BIP-39 word chips.
    /// Everything else (including Take user content rendered in the display face)
    /// must use `display(size:relativeTo:)` so the user's text-size preference is
    /// honoured.
    static func displayFixed(size: CGFloat) -> Font {
        if let name = firstAvailable(displayCandidates) {
            return .custom(name, fixedSize: size)
        }
        // System-serif fallback has no fixedSize counterpart; clamp via .system.
        return .system(size: size, weight: .regular, design: .serif).italic()
    }

    /// Interface text — DM Sans, scaling with Dynamic Type. Falls back to the
    /// system sans (rounded-neutral) when the font is not bundled.
    static func ui(_ weight: Font.Weight = .regular,
                   size: CGFloat,
                   relativeTo style: Font.TextStyle = .body) -> Font {
        let candidates: [String]
        switch weight {
        case .light: candidates = uiLightCandidates
        case .medium, .semibold, .bold: candidates = uiMediumCandidates
        default: candidates = uiRegularCandidates
        }
        if let name = firstAvailable(candidates) {
            return .custom(name, size: size, relativeTo: style).weight(weight)
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
    /// Horizontal padding of the bottom dock (each side).
    static let dockHorizontalPadding: CGFloat = 12
    /// x of the timeline spine == the dock Add button's centre, for a given
    /// container width. The dock lays out four equal columns inside
    /// `dockHorizontalPadding`, so the first column's centre sits at
    /// pad + (width − 2·pad) / 8. The spine, the Iris circles, and the Add
    /// button must all derive from this one formula — that is what keeps the
    /// spine on the + vertical at every device width.
    /// (2026-06-10 fix: this was previously a fixed `spineLeading = 32` that
    /// never matched the dock — ~26pt left of the + on a 393pt screen.)
    static func spineX(containerWidth: CGFloat) -> CGFloat {
        dockHorizontalPadding + (containerWidth - 2 * dockHorizontalPadding) / 8
    }
    /// Minimum touch target per HIG / accessibility.
    static let minTouchTarget: CGFloat = 44
    /// Standard dim-overlay opacity is baked into Color.ckDim.
}
