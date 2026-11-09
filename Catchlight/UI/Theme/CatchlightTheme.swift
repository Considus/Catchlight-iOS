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
//      they need to branch logic (e.g. mark styling), but the colours themselves
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
    static let ckInk = Color(uiColor: SceneToken.ground)
    static let ckDusk = Color(hex: 0x1C1A16)
    static let ckCatchlight = Color(hex: 0xF5EDD8)   // "catchlightCream"
    static let ckGlow = Color(uiColor: SceneToken.lit)
    static let ckEmber = Color(uiColor: SceneToken.accent)
    static let ckFog = Color(hex: 0xB8B0A3)
    static let ckShadow = Color(hex: 0x0A0908)

    // Daylight-only swatches.
    static let ckPaper = Color(hex: 0xF7F4EF)
    /// Accessible amber for text on Paper — WCAG AA (4.5:1+). Matches website `--ember-text`.
    static let ckEmberText = Color(hex: 0x856539)

    /// Accessible warm-grey for secondary text on Paper — WCAG AA. Replaces Fog in Daylight.
    static let ckSlate = Color(hex: 0x5C5650)
    // "Stone" is the Daylight mark fill — and the Important quadrant / dock-toggle
    // swatch. #E0D9CE is the owner-confirmed design value (2026-07-01; replaces the
    // provisional #E7E1D5 this shipped with while the hex was unconfirmed).
    static let ckStone = Color(hex: 0xE0D9CE)
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
}

// MARK: - Scene tokens (redesign, Cobalt)
//
// The redesign's colour roles for the Cobalt Scene, Dark and Light, from
// `Brand_System/tokens.json` in the workspace. Every semantic token below now
// resolves through these. The other four Scenes and the Scene picker arrive in the
// next slice, which generates this table from the JSON instead of hand-copying it.

enum SceneToken {
    static let ground   = UIColor.adaptive(dark: UIColor(hex: 0x0B0E2A), light: UIColor(hex: 0xF4F5FA))
    static let surface  = UIColor.adaptive(dark: UIColor(hex: 0x131840), light: UIColor(hex: 0xE8EAF5))
    static let card     = UIColor.adaptive(dark: UIColor(hex: 0x131840), light: UIColor(hex: 0xFFFFFF))
    static let raised   = UIColor.adaptive(dark: UIColor(hex: 0x1C2356), light: UIColor(hex: 0xFFFFFF))
    /// Dividers and card edges only.
    static let line     = UIColor.adaptive(dark: UIColor(hex: 0x283066), light: UIColor(hex: 0xD6DAEE))
    /// Unlit Iris lights and field outlines: 3:1 on every surface.
    static let outline  = UIColor.adaptive(dark: UIColor(hex: 0x6A7097), light: UIColor(hex: 0x81849C))
    static let text     = UIColor.adaptive(dark: UIColor(hex: 0xF6F7FF), light: UIColor(hex: 0x0B0E2A))
    static let muted    = UIColor.adaptive(dark: UIColor(hex: 0xAEB4E3), light: UIColor(hex: 0x4A5078))
    /// Text that recedes at about 4.6:1: done Task text and placeholders.
    static let faint    = UIColor.adaptive(dark: UIColor(hex: 0x888DBB), light: UIColor(hex: 0x616689))
    static let accent   = UIColor.adaptive(dark: UIColor(hex: 0xFF8AD0), light: UIColor(hex: 0x2C41E8))
    static let onAccent = UIColor.adaptive(dark: UIColor(hex: 0x0B0E2A), light: UIColor(hex: 0xFFFFFF))
    static let accentText = UIColor.adaptive(dark: UIColor(hex: 0xFFA3DA), light: UIColor(hex: 0x2C41E8))
    /// "This is on": lit lights, the Obie square and the Focus row marks. Nothing else.
    static let lit      = UIColor.adaptive(dark: UIColor(hex: 0xFFA3DA), light: UIColor(hex: 0x2C41E8))
}

extension Color {
    static let ckGround = Color(uiColor: SceneToken.ground)
    static let ckCard = Color(uiColor: SceneToken.card)
    static let ckLine = Color(uiColor: SceneToken.line)
    static let ckOutline = Color(uiColor: SceneToken.outline)
    static let ckLit = Color(uiColor: SceneToken.lit)
}

// MARK: - UIKit-facing semantic tokens (single source, shared with SwiftUI)
//
// UIKit views (the custom keyboards, the block editor) can't read the SwiftUI
// `Color` tokens, so they read these UIColors instead. The SwiftUI `ck*` tokens
// below are built ON TOP of these, so every semantic colour is defined exactly
// ONCE — adding a future appearance ("Scene") means editing only this file rather
// than re-hard-coding hex in the views. (Scene-engine Phase 1.)

enum UITheme {
    static let background    = SceneToken.ground
    static let surface       = SceneToken.card
    static let textPrimary   = SceneToken.text
    static let textSecondary = SceneToken.muted
    /// "Done" text. Mirrors `ckTextComplete`. It is text, so it clears WCAG 4.5:1 on every
    /// surface it sits on (owner 2026-10-03); `DoneTextContrastTests` measures it against the
    /// Scene tokens.
    static let textComplete  = SceneToken.faint
    /// Raw Ember FILL (both modes) — the Add droplet / Restore fill.
    static let add           = SceneToken.accent
    /// Amber FOREGROUND accent — Ember (Night) / Ember-text #856539 (Daylight, WCAG AA).
    static let accent        = SceneToken.accentText
    /// Foreground drawn ON an Ember fill — Ink in both modes.
    static let onAccent      = SceneToken.onAccent
    /// Placeholder text on an input surface: receded but passing AA, at about 4.6:1
    /// (owner 2026-08-28: secondary text read as too prominent for a placeholder).
    static let placeholder   = SceneToken.faint
}

// MARK: - Semantic, adaptive colours (Night / Daylight)
//
// These are the ONLY colours views should reference for surfaces, text, and chrome.

extension Color {
    /// Screen background — Ink (Night) / Paper (Daylight).
    static let ckBackground = Color(uiColor: UITheme.background)

    /// Elevated surface (cards, edit sheet) — Dusk (Night) / White (Daylight).
    static let ckSurface = Color(uiColor: UITheme.surface)

    /// Primary text — Catchlight cream (Night) / Ink (Daylight).
    static let ckTextPrimary = Color(uiColor: UITheme.textPrimary)

    /// Obie-emphasis text — Glow (Night) / Ember Text #856539 (Daylight, WCAG AA on Paper).
    static let ckTextObie = Color(uiColor: SceneToken.lit)

    /// Secondary / muted text — Fog (Night) / Slate #5C5650 (Daylight, WCAG AA on Paper).
    /// Fog (#B8B0A3) fails WCAG AA for body text on Paper; Slate is the accessible replacement.
    static let ckTextSecondary = Color(uiColor: UITheme.textSecondary)

    /// Completed-Task text — the receded "done" treatment (colour ONLY, no
    /// strikethrough). Tuned 2026-06-18 (owner): the original (Fog@55% / full Fog) was
    /// too close to active to tell apart; the first retune (40%/55%) went too faint.
    /// Fog @ 58% (Night) / Fog @ 82% (Daylight) — receded but a touch darker than the
    /// 50%/75% pass (owner 2026-06-18: "could be made a little darker"), still clearly
    /// distinct from active. Raised 2026-10-03 to clear WCAG 4.5:1 (owner: contrast
    /// minimums regardless): Fog @ 76% (Night) / #746E68 (Daylight), see `UITheme.textComplete`. Single token: the Angle, the inline editor, and the
    /// timeline card all recede by the same amount.
    static let ckTextComplete = Color(uiColor: UITheme.textComplete)

    /// The Add button — Ember (both).
    static let ckAdd = Color(uiColor: UITheme.add)

    /// Active navigation icon — Ember (both).
    static let ckNavActive = Color(uiColor: SceneToken.accentText)

    /// Inactive navigation icon — Catchlight @ 55% (Night) / Fog (Daylight).
    static let ckNavInactive = Color(uiColor: SceneToken.muted)

    /// Amber accent for FOREGROUND content (text or iconography) drawn on a
    /// background SURFACE — Ember (Night) / Ember Text #856539 (Daylight).
    /// Use this — NOT raw `ckEmber` — for any amber glyph or label sitting on
    /// `ckBackground` / `ckSurface`: dock icons, settings-row icons, timeline
    /// banner action labels. Raw Ember (#C9A96E) on Paper is only ~2:1 and
    /// fails both WCAG AA text (4.5:1) and UI-component (3:1) contrast; #856539
    /// gives 4.9:1 on Paper and 5.4:1 on white. Night is UNCHANGED (resolves to
    /// Ember). Raw `ckEmber` / `ckAdd` remain the FILL colour (Add droplet,
    /// selection borders, pill fills), where Ember is correct.
    /// (Accessibility audit 7.6, 2026-06-13.)
    static let ckAccent = Color(uiColor: UITheme.accent)

    /// Foreground drawn ON an Ember fill (the Add "+", active filter glyphs):
    /// Ink in BOTH modes. Night was already Ink-coloured (it used `ckBackground`
    /// = Ink), so this is unchanged there; in Daylight it replaces Paper-on-Ember
    /// (2.04:1, fails) with Ink-on-Ember (8.62:1). Use for amber-filled chrome
    /// controls. NOTE: the locked primary CTAs (DockPill, Paywall) are a
    /// separate owner call (see audit C4) and are NOT switched here.
    static let ckOnAccent = Color(uiColor: UITheme.onAccent)

    /// The veil — the ONE obscuring overlay for the Focus row, the editor, and the
    /// Settings backdrop (owner decision 2026-06-11: solid 90% background veil
    /// everywhere; no blur, no dark tint in Daylight). Ink @ 90% (Night) /
    /// Paper @ 90% (Daylight). The screens beneath stay full-opacity — the
    /// veil alone provides the recede.
    static let ckDim = Color(uiColor: SceneToken.ground.withAlphaComponent(0.90))

    // MARK: - Take card variants (HiFi v1.7 .card — section 5)
    //
    // The Take card surface is `ckSurface` (White Daylight / Dusk Night). These
    // tokens cover the two variant treatments v1.7 layers on top. Added 2026-06-14
    // (fix pass 1).

    /// Obie card BACKGROUND — a warm tint distinct from the plain surface so the
    /// pinned Take reads as special. Daylight #FBF8F3 (Ember @8% blended onto
    /// White, solid to prevent spine bleed) / Night #2D2921. (HiFi v1.7 .obie-card)
    static let ckCardObieSurface = Color(uiColor: SceneToken.raised)

    /// Obie card BORDER — Ember @65% (Daylight) / Glow @65% (Night). The Ember
    /// border is reserved EXCLUSIVELY for the Obie. (HiFi v1.7 .obie-card)
    static let ckCardObieBorder = Color(uiColor: SceneToken.lit)

    /// Overdue card BORDER (reminder date passed). RUBY (owner 2026-06-18 — the Take
    /// border/colour system): overdue now reads as an ALERT, not warm amber, and ruby
    /// is the only state that overrides the Obie's gold border. Same hue as `ckRuby`.
    static let ckCardOverdueBorder = Color(uiColor: .adaptive(
        dark: UIColor(red: 0.86, green: 0.32, blue: 0.32, alpha: 1.0),
        light: UIColor(red: 0.72, green: 0.18, blue: 0.18, alpha: 1.0)
    ))

    /// Overdue reminder META TEXT (`.tm.overdue`) — RUBY, matching the overdue border
    /// (owner 2026-06-18). The subtext is italic ONLY when overdue, so the ruby + slant
    /// together read as "this one's late." Same hue as `ckRuby` / `ckCardOverdueBorder`.
    static let ckTextOverdue = Color(uiColor: .adaptive(
        dark: UIColor(red: 0.86, green: 0.32, blue: 0.32, alpha: 1.0),
        light: UIColor(red: 0.72, green: 0.18, blue: 0.18, alpha: 1.0)
    ))

    /// Done card BORDER (a fully-ticked Task or a reminder marked done). It IS the done-text
    /// grey, built from the same token so the two can't drift: "done" recedes by the same
    /// amount whether it's the edge or the words (owner 2026-06-18, reaffirmed 2026-10-03
    /// when the grey was darkened for contrast). `DoneTextContrastTests` holds it.
    static let ckCardDoneBorder = Color(uiColor: UITheme.textComplete)

    /// Error / warning accent — used by the non-blocking error strips on the
    /// timeline (Task 3.9). Same hue in both modes so the strip reads as an
    /// alert regardless of theme; brightness chosen to remain WCAG AA against
    /// `ckTextPrimary`. Strips themselves use this colour at ~12–15% opacity.
    static let ckRuby = Color(uiColor: .adaptive(
        dark: UIColor(red: 0.86, green: 0.32, blue: 0.32, alpha: 1.0),
        light: UIColor(red: 0.72, green: 0.18, blue: 0.18, alpha: 1.0)
    ))

}

// MARK: - Quadrant / mark fills (mode-dependent — resolved by the caller)
//
// These need the active colour scheme because the same activity reads differently
// per mode. Views pass their `@Environment(\.colorScheme)` in.

// Per-TYPE fill colours (position was set by the old Iris's N/E/S/W diamond —
// Note=top, Task=right, Remind=left, Reserved=bottom). Daylight values are the
// HiFi v1.6.9 `--q-*` swatches (the canonical look the owner reviews). v1.6.9
// moved the Ember accent from Remind onto TASK, so Task is the warm quadrant
// and Remind is the lighter amber. (Supersedes the DS §5.2 Ink-tint
// Daylight values — flagged for DS reconciliation.)
enum Quadrant {
    // Daylight fills raised 2026-06-18 (owner-approved) to meet WCAG 1.4.11 (≥3:1 on
    // the white card): Note #BCBCBB→#8C8C8C (~1.9→~3.1:1), Task Ember #C9A96E→#A8843E
    // (~2→~3.5:1), Remind #B5A283→#8A7A58 (~2→~3.7:1). Night values unchanged (already
    // light-on-dark). Supersedes the v1.6.9 `--q-*` swatches for Daylight.
    //
    // The Daylight fills are named here so they live in ONE editable place rather
    // than as inline magic numbers inside each accessor.
    private static let noteDay   = Color(hex: 0x8C8C8C)   // ~3.1:1 on the white card
    private static let taskDay   = Color(hex: 0xA8843E)   // ~3.5:1 on the white card
    private static let remindDay = Color(hex: 0x8A7A58)   // ~3.7:1 on the white card

    /// Note — Daylight grey / Night Catchlight @ 55%.
    static func note(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.ckCatchlight.opacity(0.55) : noteDay
    }

    /// Task — the warm accent; Daylight darkened to a 3:1 amber, Night keeps Ember.
    static func task(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .ckEmber : taskDay
    }

    /// Remind — Daylight darkened to a 3:1 tan / Night Glow @ 65%.
    static func reminder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.ckGlow.opacity(0.65) : remindDay
    }

    /// Important — the Iris North wedge (owner 2026-06-20, indicator only). Uses the
    /// two previously-unused brand swatches, paired for legibility per mode: Shadow
    /// #0A0908 (near-black, ~20:1 on the white card) in Daylight, Stone #E0D9CE
    /// (light warm stone, light-on-dark) in Night. Shown on an Obie too (an Obie
    /// auto-flags Important; owner wants the flag visible there alongside the ring).
    static func important(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .ckStone : .ckShadow
    }
}

// MARK: - Daylight card shadow (Design System v1.1 §4.1)

/// The standard Take-card shadow for ckSurface cards/chips on Paper: ambient
/// `0 2px 8px rgba(15,14,12,0.09)` + contact `0 1px 2px rgba(15,14,12,0.05)`.
/// Daylight ONLY — DS §4 prohibits shadows in Night, where elevation is the
/// Dusk surface colour. CSS blur ≈ 2× SwiftUI radius, hence radius 4/1.
struct DaylightCardShadow: ViewModifier {
    /// Overdue Takes get a slightly stronger Daylight shadow (HiFi v1.7
    /// .card.overdue: `0 2px 10px rgba(15,14,12,0.13), 0 1px 3px …0.08`) — the
    /// dark overdue border absorbs the subtle default, so it's lifted a touch.
    var strong: Bool = false
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .shadow(color: scheme == .dark ? .clear : Color.ckInk.opacity(strong ? 0.13 : 0.09),
                    radius: strong ? 5 : 4, y: 2)
            .shadow(color: scheme == .dark ? .clear : Color.ckInk.opacity(strong ? 0.08 : 0.05),
                    radius: strong ? 1.5 : 1, y: 1)
    }
}

extension View {
    func daylightCardShadow(strong: Bool = false) -> some View {
        modifier(DaylightCardShadow(strong: strong))
    }
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
    /// ROMAN (upright) Cormorant Garamond — the same bundled face as the italic
    /// candidates, but the non-italic cut. The `display*` candidates lead with
    /// `CormorantGaramond-LightItalic`, so every "display" use renders italic;
    /// these lead with the roman PostScript names so headings that must be
    /// upright (the DAILIES page heading — section 3) resolve correctly. The
    /// fallback is the system serif WITHOUT `.italic()`.
    private static let displayRomanCandidates = [
        "CormorantGaramond-Light",   // confirmed PS name of CormorantGaramond[wght].ttf
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

    /// The face the display (Cormorant) text falls back to for characters it has no
    /// glyph for, by app language. Cormorant and DM Sans cover Latin scripts only, so
    /// iOS fills Japanese, Korean, Chinese and Thai from its own fonts. Its default is a
    /// sans, which suits the DM Sans text but loses the serif of the display face.
    /// Japanese has an iOS serif to pair with it, Hiragino Mincho; Korean, Chinese and
    /// Thai have none on iOS, so they keep the system sans (Apple SD Gothic Neo, PingFang,
    /// Thonburi), which needs no change (owner 2026-10-06).
    static func displayFallback(for language: String?) -> String? {
        language == "ja" ? "HiraMinProN-W3" : nil
    }

    private static var displayFallbackName: String? {
        displayFallback(for: Bundle.main.preferredLocalizations.first)
    }

    /// `font` with the language's display fallback first in its cascade list, or
    /// `font` unchanged when the language has none.
    private static func withDisplayFallback(_ font: UIFont) -> UIFont {
        guard let name = displayFallbackName else { return font }
        let cascade = [UIFontDescriptor(name: name, size: font.pointSize)]
        let descriptor = font.fontDescriptor.addingAttributes([.cascadeList: cascade])
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    /// A display face as a SwiftUI font with the language's fallback, scaled for
    /// Dynamic Type like `.custom(_:size:relativeTo:)`. Nil when there is no fallback,
    /// so callers keep the plain custom font.
    private static func cascaded(_ name: String, size: CGFloat, relativeTo style: Font.TextStyle?) -> Font? {
        guard displayFallbackName != nil, let base = UIFont(name: name, size: size) else { return nil }
        let font = withDisplayFallback(base)
        guard let style else { return Font(font) }
        return Font(UIFontMetrics(forTextStyle: uiTextStyle(style)).scaledFont(for: font))
    }

    private static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }

    /// Display / Take text — Cormorant Garamond Italic, scaling with Dynamic
    /// Type. Falls back to the system serif (italic) when the font is not bundled.
    /// Use for USER CONTENT rendered in the display face (e.g. Take body text on
    /// rows / edit sheet) — content must respect the user's text size preference.
    static func display(size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        if let name = firstAvailable(displayCandidates) {
            return cascaded(name, size: size, relativeTo: style) ?? .custom(name, size: size, relativeTo: style)
        }
        return .system(style, design: .serif).italic()
    }

    /// Display ROMAN (upright) — Cormorant Garamond Light, scaling with Dynamic
    /// Type. Use for display-face text that must NOT be italic: the pinned
    /// DAILIES / SEQUENCE / SEARCH page heading (section 3). Take BODY text stays
    /// italic via `display(size:)` — the display face is intentionally italic for
    /// Take content. Falls back to the system serif (upright, no `.italic()`).
    static func displayRoman(size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        if let name = firstAvailable(displayRomanCandidates) {
            return cascaded(name, size: size, relativeTo: style) ?? .custom(name, size: size, relativeTo: style)
        }
        return .system(style, design: .serif)
    }

    /// Display / brand headings — Cormorant Garamond Italic at a FIXED point size
    /// that does NOT respond to Dynamic Type. Use ONLY for brand display: the
    /// wordmark, onboarding headings, the Obie title treatment, BIP-39 word chips.
    /// Everything else (including Take user content rendered in the display face)
    /// must use `display(size:relativeTo:)` so the user's text-size preference is
    /// honoured.
    static func displayFixed(size: CGFloat) -> Font {
        if let name = firstAvailable(displayCandidates) {
            return cascaded(name, size: size, relativeTo: nil) ?? .custom(name, fixedSize: size)
        }
        // System-serif fallback has no fixedSize counterpart; clamp via .system.
        return .system(size: size, weight: .regular, design: .serif).italic()
    }

    /// UIKit counterpart of `display(size:)` for `UIViewRepresentable` text
    /// surfaces (the block editor's `UITextView` rows). Scales with Dynamic Type
    /// via `UIFontMetrics(.body)`. Falls back to the system serif italic when the
    /// bundled face isn't present — matching `display`'s SwiftUI fallback.
    static func uiDisplay(size: CGFloat) -> UIFont {
        let base: UIFont
        if let name = firstAvailable(displayCandidates), let custom = UIFont(name: name, size: size) {
            base = withDisplayFallback(custom)
        } else {
            let descriptor = UIFont.systemFont(ofSize: size).fontDescriptor
                .withDesign(.serif)?
                .withSymbolicTraits(.traitItalic)
            base = descriptor.map { UIFont(descriptor: $0, size: size) }
                ?? UIFont.italicSystemFont(ofSize: size)
        }
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
    }

    /// UIKit DM Sans — the `ui()` counterpart for `UIViewRepresentable` text
    /// surfaces (the block editor's `UITextView` rows). Take content is DM Sans,
    /// never the display face (DS §2.2). Scales via UIFontMetrics(.body).
    static func uiBody(size: CGFloat, weight: Font.Weight = .regular) -> UIFont {
        let candidates: [String]
        switch weight {
        case .light: candidates = uiLightCandidates
        case .medium, .semibold, .bold: candidates = uiMediumCandidates
        default: candidates = uiRegularCandidates
        }
        let base = firstAvailable(candidates).flatMap { UIFont(name: $0, size: size) }
            ?? UIFont.systemFont(ofSize: size)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
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
    /// Diameter of a Take circle (Iris) on the timeline. Owner 2026-06-15:
    /// enlarged 22 → 44 to FILL the 44pt touch frame and match the dock buttons
    /// (which were also taken to 44 the same day) — the Iris and the dock share
    /// the HiFi `--iris` token by design, and 22 had drifted below even the HiFi's
    /// 36. Row spacing is unaffected (the touch frame was already 44). The spine
    /// and Add-button alignment math below is parametric on this, so it follows.
    /// (Search/sequence results reuse the timeline row; the edit footer, conflict
    /// view, and Focus row pass their own explicit diameters and are unaffected.)
    static let circleDiameter: CGFloat = 44
    /// The distance from the dock's first column centre (`spineX`) to the Take card's
    /// leading edge: the card starts at `spineX − cardLeadingOffset`, about 20pt from
    /// the screen edge, matching the 20pt trailing margin. The timeline line that once
    /// ran down `spineX` is gone (owner 2026-11-09); the Add button still sits there.
    static let cardLeadingOffset: CGFloat = 38
    /// The Take card's inner padding on every side.
    static let cardPadding: CGFloat = 14
    /// The Iris's top and leading offset inside its card.
    static let irisInset: CGFloat = 14
    /// The gap between the Iris's trailing edge and the card's text column.
    static let irisTextGap: CGFloat = 12
    /// The Take card's internal LEADING text padding: the text column starts clear of
    /// the Iris in the card's top-left. The DAILIES heading and month markers align to
    /// the same column.
    static let cardTextLeadingPad: CGFloat = irisInset + circleDiameter + irisTextGap
    /// The shortest a Take card may be: room for the Iris with `irisInset` above and below.
    static let cardMinHeight: CGFloat = irisInset * 2 + circleDiameter
    /// The spacing setting's gaps were tuned with the old Iris's top half hanging into them.
    /// A fixed 22, not `circleDiameter / 2`: it is what the old Iris took up, so a future
    /// Iris resize must not change anyone's spacing.
    static let retiredIrisOverhang: CGFloat = 22
    /// The smallest visible gap between two Take cards.
    static let minCardGap: CGFloat = 10
    /// The visible gap between two Take cards for a stored spacing setting: the setting less
    /// the room the old straddling Iris took, so each setting looks as it did, never below
    /// `minCardGap`. Dailies and the Storyboard both use it, so they stay equal.
    static func visibleCardGap(for setting: CGFloat) -> CGFloat {
        max(minCardGap, setting - retiredIrisOverhang)
    }
    /// The card's standard TRAILING text pad. Tokenised 2026-08-15 because the
    /// manual-order drag handle has to inset the body text by exactly enough to clear
    /// itself, and a literal 14 in two files would drift the moment either moved.
    /// Unchanged in value — this is the same 14 the card has always used.
    static let cardTextTrailingPad: CGFloat = 14
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

    /// Vertical space the pinned timeline heading + its 12pt fade occupy BELOW
    /// the device top inset (≈ 14 top pad + ~24 title + 2 + 12 fade). The
    /// timeline's top content padding is `deviceTopInset + headingClearance` so
    /// the first row always clears the heading and the fade on large-inset
    /// devices (iPhone 17 / iOS 26.5.1). The previous fixed
    /// `52` ignored the inset, tucking the first Take under the fade.
    /// The gap between the heading block's bottom and the first Take / pinned Obie. Was
    /// implicit inside the 68 above; named in round 2 (2026-09-04) so the clearance can be
    /// derived from the heading's MEASURED height at large text sizes instead of a constant
    /// that only ever suited the 24pt heading. 68 − (14 top pad + ~29 text + 2 bottom pad).
    static let headingBelowGap: CGFloat = 23

    static let headingClearance: CGFloat = 68   // 52 → 58 → 66 → 68: drop the topmost Take/Obie lower so it clears the fade (owner 2026-06-16; +8 with the pinned-Obie header; +2 on 2026-06-29 when the heading grew 20 → 24, pushing the fade lower)
    /// Resting clearance the dock occupies above the timeline's bottom, BEFORE
    /// the device bottom inset is added. Last-row bottom padding is
    /// `dockClearance + deviceBottomInset` so the final Take clears the raised dock.
    static let dockClearance: CGFloat = 120
    /// The dock's own resting bottom padding above the home indicator, added on
    /// top of `deviceBottomInset` (BottomDockView / DockPillRow).
    static let dockBottomPadding: CGFloat = 8
    /// Gap between the brand mark (`IntroBrandMark`) and the hero line on the
    /// intro surfaces — onboarding steps AND the app-entry LockView reference this
    /// one value so the mark→hero rhythm is identical and can't drift (owner
    /// 2026-06-16 "set position"; shared 2026-06-29).
    static let introHeroTopGap: CGFloat = 112
    /// Letter-spacing for the page heading (DAILIES / SEQUENCE / STORYBOARD / SHOT
    /// LIST / SETTINGS).
    static let pageHeadingKerning: CGFloat = 1.6
    /// Leading inset `pageHeadingStyle` adds to optically centre the kerned title.
    /// `.kerning` adds trailing space after the last glyph (~half a glyph more than
    /// the kern value itself), pulling a plainly-centred title left; 3.0 lands the
    /// ink dead-centre — measured on DAILIES, 601→603px (owner 2026-06-29).
    static let pageHeadingKerningComp: CGFloat = 3.0
}

extension View {
    /// The one page-heading style — Cormorant Garamond ROMAN 24, kerned, centred,
    /// `ckTextPrimary`. Shared by every screen's heading so they can't drift (the
    /// catalogue documents this once). `.kerning` adds its spacing AFTER the last
    /// glyph too, so a plainly-centred kerned title sits ~half a kern left of true
    /// centre; the matching `.padding(.leading)` cancels that trailing space so the
    /// letters read dead-centre (owner 2026-06-29).
    func pageHeadingStyle() -> some View {
        self
            .font(CatchlightFont.displayRoman(size: 24, relativeTo: .title3))
            .kerning(CatchlightLayout.pageHeadingKerning)
            .foregroundStyle(Color.ckTextPrimary)
            .padding(.leading, CatchlightLayout.pageHeadingKerningComp)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
