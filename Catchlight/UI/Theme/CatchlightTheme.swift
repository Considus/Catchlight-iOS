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

    /// Completed-Task text — the receded "done" treatment (colour ONLY, no
    /// strikethrough). Strengthened 2026-06-18 (owner: the old Fog@55% / full-Fog read
    /// too close to active text to tell done from not-done) — now clearly more faded:
    /// Fog @ 40% (Night) / Fog @ 55% (Daylight). Single token, so the Angle, the inline
    /// editor, and the timeline card all recede by the same amount.
    static let ckTextComplete = Color(uiColor: .adaptive(dark: Palette.fog.withAlphaComponent(0.40),
                                                         light: Palette.fog.withAlphaComponent(0.55)))

    /// The timeline spine — Catchlight @ 18% (Night) / Ink @ 13% (Daylight).
    static let ckSpine = Color(uiColor: .adaptive(
        dark: Palette.catchlight.withAlphaComponent(0.18),
        light: Palette.ink.withAlphaComponent(0.13)
    ))

    /// The live "wire" colour of the timeline spine — Ember @ 35%, matching the
    /// dock buttons' ring (`dockRing()`) so the wire and toolbar read as one family
    /// (owner 2026-06-16). Single-sourced because the wire is now drawn in TWO
    /// places that MUST stay identical: the gutter spine (`DailiesView`, behind the
    /// cards) and the short segment that threads each Iris aperture (`TakeRowView`,
    /// above the card / behind the ring — "rings on a wire"). (`ckSpine` above is
    /// the older, fainter tint still used by onboarding + the conflict view.)
    static var ckSpineWire: Color { ckAccent.opacity(0.35) }

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

    // MARK: - Take card variants (HiFi v1.7 .card — section 5)
    //
    // The Take card surface is `ckSurface` (White Daylight / Dusk Night). These
    // tokens cover the two variant treatments v1.7 layers on top. Added 2026-06-14
    // (fix pass 1, D-040) — record in the Design System.

    /// Obie card BACKGROUND — a warm tint distinct from the plain surface so the
    /// pinned Take reads as special. Daylight #FBF8F3 (Ember @8% blended onto
    /// White, solid to prevent spine bleed) / Night #2D2921. (HiFi v1.7 .obie-card)
    static let ckCardObieSurface = Color(uiColor: .adaptive(
        dark: UIColor(hex: 0x2D2921),
        light: UIColor(hex: 0xFBF8F3)
    ))

    /// Obie card BORDER — Ember @65% (Daylight) / Glow @65% (Night). The Ember
    /// border is reserved EXCLUSIVELY for the Obie. (HiFi v1.7 .obie-card)
    static let ckCardObieBorder = Color(uiColor: .adaptive(
        dark: Palette.glow.withAlphaComponent(0.65),
        light: Palette.ember.withAlphaComponent(0.65)
    ))

    /// Overdue card BORDER (reminder date passed) — solid overdue amber #6B4508
    /// (Daylight, matches the v1.7 overdue text token) / Glow @35% (Night).
    /// Clearly distinct from the Obie Ember. (HiFi v1.7 .card.overdue, DS §12.3)
    static let ckCardOverdueBorder = Color(uiColor: .adaptive(
        dark: Palette.glow.withAlphaComponent(0.35),
        light: UIColor(hex: 0x6B4508)
    ))

    /// Overdue reminder META TEXT (`.tm.overdue`) — #6B4508 (Daylight, same as the
    /// border) but FULL Glow in Night, NOT the Glow@35% the BORDER uses: HiFi v1.7
    /// `.night .tm.overdue{color:var(--glow)}` keeps the overdue time legible while
    /// the border stays a quiet @35%. (DS §12.3 — was incorrectly sharing the border
    /// token, so Night overdue times read too faint; owner 2026-06-16.)
    static let ckTextOverdue = Color(uiColor: .adaptive(
        dark: Palette.glow,
        light: UIColor(hex: 0x6B4508)
    ))

    /// Iris OFF-quadrant annular fill (HiFi v1.7 `--q-off` — section 7). The
    /// faint backing band that makes the Iris read as a complete RING (with a
    /// hollow centre aperture) even when only some quadrants are active. Daylight
    /// #F1F1F0 / Night #1B1916. Replaces the old solid base disc, which filled the
    /// centre and defeated the hollow-aperture read.
    static let ckIrisOff = Color(uiColor: .adaptive(
        dark: UIColor(hex: 0x1B1916),
        light: UIColor(hex: 0xF1F1F0)
    ))

    /// Iris hairline OUTER ring (HiFi v1.7 — section 7). Daylight #E7E7E7 (the
    /// v1.7 iris SVG uses the near-identical #ECECEC); Night rides the divider /
    /// spine line token (Catchlight @18%) so it reads as a faint warm rim on Ink
    /// rather than the bright Daylight grey.
    static let ckIrisRing = Color(uiColor: .adaptive(
        dark: Palette.catchlight.withAlphaComponent(0.18),
        light: UIColor(hex: 0xE7E7E7)
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

// Per-TYPE fill colours (position is set by TakeCircleView's N/E/S/W diamond —
// Note=top, Task=right, Remind=left, Reserved=bottom). Daylight values are the
// HiFi v1.6.9 `--q-*` swatches (the canonical look the owner reviews). v1.6.9
// moved the Ember accent from Remind onto TASK, so Task is the warm quadrant
// and Remind is the lighter amber. (D-042; supersedes the DS §5.2 Ink-tint
// Daylight values — flagged for DS reconciliation, sub-decision D-S1.)
enum Quadrant {
    /// Note — Daylight grey `#BCBCBB` (HiFi `--q-note`) / Night Catchlight @ 55%.
    static func note(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.ckCatchlight.opacity(0.55) : Color(hex: 0xBCBCBB)
    }

    /// Task — the warm Ember accent (HiFi `--q-task` `#C9A96E`), both modes.
    static func task(_ scheme: ColorScheme) -> Color { .ckEmber }

    /// Remind — Daylight `#B5A283` (HiFi `--q-remind`, 50% tint of overdue) /
    /// Night Glow @ 65% (a distinct gold from Task's Ember).
    static func reminder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.ckGlow.opacity(0.65) : Color(hex: 0xB5A283)
    }

    /// Obie ring around the whole circle — Glow (Night) / Ember (Daylight).
    /// Also the colour of the Obie specular-dot core (DS §5.4).
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

    /// Display ROMAN (upright) — Cormorant Garamond Light, scaling with Dynamic
    /// Type. Use for display-face text that must NOT be italic: the pinned
    /// DAILIES / SEQUENCE / SEARCH page heading (section 3). Take BODY text stays
    /// italic via `display(size:)` — the display face is intentionally italic for
    /// Take content. Falls back to the system serif (upright, no `.italic()`).
    static func displayRoman(size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        if let name = firstAvailable(displayRomanCandidates) {
            return .custom(name, size: size, relativeTo: style)
        }
        return .system(style, design: .serif)
    }

    /// Fixed-size roman counterpart of `displayRoman` for callers that must NOT
    /// scale with Dynamic Type (brand display chrome). Falls back to the upright
    /// system serif.
    static func displayRomanFixed(size: CGFloat) -> Font {
        if let name = firstAvailable(displayRomanCandidates) {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: .regular, design: .serif)
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

    /// UIKit counterpart of `display(size:)` for `UIViewRepresentable` text
    /// surfaces (the block editor's `UITextView` rows). Scales with Dynamic Type
    /// via `UIFontMetrics(.body)`. Falls back to the system serif italic when the
    /// bundled face isn't present — matching `display`'s SwiftUI fallback.
    static func uiDisplay(size: CGFloat) -> UIFont {
        let base: UIFont
        if let name = firstAvailable(displayCandidates), let custom = UIFont(name: name, size: size) {
            base = custom
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
    /// never the display face (DS §2.2 / D-042). Scales via UIFontMetrics(.body).
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
    /// view, and petal fan pass their own explicit diameters and are unaffected.)
    static let circleDiameter: CGFloat = 44
    /// Width of the timeline spine.
    static let spineWidth: CGFloat = 2
    /// The Take card's leading edge sits this far LEFT of the spine. Two things ride
    /// on it together (which is what keeps the Iris ON the spine): the row's leading
    /// padding is `spineX − cardSpineInset` (the card's left edge), and TakeRowView
    /// offsets the Iris by `cardSpineInset − circleDiameter/2` so the Iris re-centres
    /// on the spine. Owner 2026-06-16: raised 24 → 38 so the card's LEFT margin
    /// (`spineX − 38` ≈ 20pt) matches the 20pt RIGHT margin — the card grows ~14pt
    /// wider and the Iris nests a little deeper into its top-left region (the Iris
    /// stays pinned to the spine under the + button). Deliberately independent of
    /// `circleDiameter` so resizing the Iris never moves or narrows the card.
    static let cardSpineInset: CGFloat = 38
    /// The Take card's internal LEADING text padding — sized so the text column
    /// begins exactly at the Iris's EASTERN edge, leaving the Iris in a clear left
    /// gutter with NO text left of the spine (owner 2026-06-16). card-left is
    /// `spineX − cardSpineInset`, the Iris east edge is `spineX + circleDiameter/2`,
    /// so the pad = circleDiameter/2 + cardSpineInset. The DAILIES heading + month
    /// markers align to the same x (`spineX + circleDiameter/2`). Trailing/bottom
    /// stay at the standard 14.
    static let cardTextLeadingPad: CGFloat = circleDiameter / 2 + cardSpineInset
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
    /// devices (iPhone 17 / iOS 26.5.1 — section 4 / D-041). The previous fixed
    /// `52` ignored the inset, tucking the first Take under the fade.
    static let headingClearance: CGFloat = 66   // 52 → 58 → 66: drop the topmost Take/Obie lower so it clears the fade (owner 2026-06-16; +8 with the pinned-Obie header)
    /// Resting clearance the dock occupies above the timeline's bottom, BEFORE
    /// the device bottom inset is added. Last-row bottom padding is
    /// `dockClearance + deviceBottomInset` so the final Take clears the raised dock.
    static let dockClearance: CGFloat = 120
    /// The dock's own resting bottom padding above the home indicator, added on
    /// top of `deviceBottomInset` (BottomDockView / DockPillRow).
    static let dockBottomPadding: CGFloat = 8
}
