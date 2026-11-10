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
    static let ckInk = Color(SceneColor(\.ground))
    static let ckDusk = Color(hex: 0x1C1A16)
    static let ckCatchlight = Color(hex: 0xF5EDD8)   // "catchlightCream"
    static let ckGlow = Color(SceneColor(\.lit))
    static let ckEmber = Color(SceneColor(\.accent))
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

// MARK: - The stored Scene

extension CatchlightScene {
    /// The key the chosen Scene is stored under, as its raw value.
    static let defaultsKey = "catchlight.scene"

    /// The app group store, so the share sheet (and later the widgets) read the same choice.
    /// One instance, so a write from `SceneChoice.select` reaches the Settings row's
    /// `@AppStorage`, which watches this same object. A missing App Group is a setup error
    /// (as in `AppGroup.containerURL()`): debug builds stop, and a release build falls back
    /// to the standard store, so the row and the applied Scene still share one store.
    static let sharedDefaults: UserDefaults = {
        guard let group = UserDefaults(suiteName: AppGroup.identifier) else {
            assertionFailure("App Group \(AppGroup.identifier) is not configured: check entitlements.")
            return .standard
        }
        return group
    }()

    /// The stored Scene, or Cobalt when the key is absent or holds an unknown value.
    static func stored(in defaults: UserDefaults? = sharedDefaults) -> CatchlightScene {
        defaults?.string(forKey: defaultsKey).flatMap(CatchlightScene.init(rawValue:)) ?? .default
    }
}

// MARK: - The Scene trait

/// The chosen Scene, carried as a UIKit trait so every dynamic `SceneToken` colour reads it.
struct SceneTrait: UITraitDefinition {
    static let defaultValue = CatchlightScene.default
    static let identifier = "app.catchlight.scene"
    static let name = "CatchlightScene"
}

/// The same Scene in SwiftUI's environment, bridged both ways to `SceneTrait`, so every
/// hosting controller reads the trait its window carries.
struct SceneEnvironmentKey: EnvironmentKey, UITraitBridgedEnvironmentKey {
    static let defaultValue = CatchlightScene.default
    static func read(from traitCollection: UITraitCollection) -> CatchlightScene {
        traitCollection[SceneTrait.self]
    }
    static func write(to mutableTraits: inout UIMutableTraits, value: CatchlightScene) {
        mutableTraits[SceneTrait.self] = value
    }
}

extension EnvironmentValues {
    var catchlightScene: CatchlightScene {
        get { self[SceneEnvironmentKey.self] }
        set { self[SceneEnvironmentKey.self] = newValue }
    }
}

/// A Scene colour role for SwiftUI. It resolves from the environment's Scene and colour
/// scheme, which SwiftUI tracks, so a Scene change repaints every `ck*` colour. Do not build
/// a `ck*` colour as `Color(uiColor:)` on a `SceneToken`: SwiftUI can keep that resolved
/// value when only the custom trait changes, and the open Settings sheet then stays on the
/// old Scene.
struct SceneColor: ShapeStyle, Hashable {
    let role: KeyPath<ScenePalette, UInt32>
    var opacity: Double = 1

    init(_ role: KeyPath<ScenePalette, UInt32>, opacity: Double = 1) {
        self.role = role
        self.opacity = opacity
    }

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        let hex = environment.catchlightScene.palette(dark: environment.colorScheme == .dark)[keyPath: role]
        return Color.Resolved(colorSpace: .sRGB,
                              red: Float((hex >> 16) & 0xFF) / 255,
                              green: Float((hex >> 8) & 0xFF) / 255,
                              blue: Float(hex & 0xFF) / 255,
                              opacity: Float(opacity))
    }
}

// MARK: - Scene tokens
//
// The redesign's colour roles. Each resolves per Scene and appearance from the generated
// palettes in `SceneTokens.generated.swift`, reading the Scene from `SceneTrait`, so a
// Scene change re-resolves every colour in place. Every semantic token below resolves
// through these.

enum SceneToken {
    static let ground   = role(\.ground)
    static let surface  = role(\.surface)
    static let card     = role(\.card)
    static let raised   = role(\.raised)
    /// Dividers and card edges only.
    static let line     = role(\.line)
    /// Field outlines: 3:1 on every surface.
    static let outline  = role(\.outline)
    /// Unlit Iris lights: softer than `outline`, 2:1 on every surface.
    static let unlit    = role(\.unlit)
    static let text     = role(\.text)
    static let muted    = role(\.muted)
    /// Text that recedes at about 4.6:1: done Task text and placeholders.
    static let faint    = role(\.faint)
    static let accent   = role(\.accent)
    static let onAccent = role(\.onAccent)
    static let accentText = role(\.accentText)
    /// "This is on": lit lights, the Obie square and the Focus row marks. Nothing else.
    static let lit      = role(\.lit)

    private static func role(_ key: KeyPath<ScenePalette, UInt32>) -> UIColor {
        UIColor { traits in
            let palette = traits[SceneTrait.self].palette(dark: traits.userInterfaceStyle == .dark)
            return UIColor(hex: palette[keyPath: key])
        }
    }
}

extension Color {
    static let ckGround = Color(SceneColor(\.ground))
    static let ckCard = Color(SceneColor(\.card))
    static let ckLine = Color(SceneColor(\.line))
    static let ckOutline = Color(SceneColor(\.outline))
    static let ckUnlit = Color(SceneColor(\.unlit))
    static let ckLit = Color(SceneColor(\.lit))
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
    static let ckBackground = Color(SceneColor(\.ground))

    /// Elevated surface (cards, edit sheet) — Dusk (Night) / White (Daylight).
    static let ckSurface = Color(SceneColor(\.card))

    /// Primary text — Catchlight cream (Night) / Ink (Daylight).
    static let ckTextPrimary = Color(SceneColor(\.text))

    /// Obie-emphasis text — Glow (Night) / Ember Text #856539 (Daylight, WCAG AA on Paper).
    static let ckTextObie = Color(SceneColor(\.lit))

    /// Secondary / muted text — Fog (Night) / Slate #5C5650 (Daylight, WCAG AA on Paper).
    /// Fog (#B8B0A3) fails WCAG AA for body text on Paper; Slate is the accessible replacement.
    static let ckTextSecondary = Color(SceneColor(\.muted))

    /// Completed-Task text — the receded "done" treatment (colour ONLY, no
    /// strikethrough). Tuned 2026-06-18 (owner): the original (Fog@55% / full Fog) was
    /// too close to active to tell apart; the first retune (40%/55%) went too faint.
    /// Fog @ 58% (Night) / Fog @ 82% (Daylight) — receded but a touch darker than the
    /// 50%/75% pass (owner 2026-06-18: "could be made a little darker"), still clearly
    /// distinct from active. Raised 2026-10-03 to clear WCAG 4.5:1 (owner: contrast
    /// minimums regardless): Fog @ 76% (Night) / #746E68 (Daylight), see `UITheme.textComplete`. Single token: the Angle, the inline editor, and the
    /// timeline card all recede by the same amount.
    static let ckTextComplete = Color(SceneColor(\.faint))

    /// The Add button — Ember (both).
    static let ckAdd = Color(SceneColor(\.accent))

    /// Active navigation icon — Ember (both).
    static let ckNavActive = Color(SceneColor(\.accentText))

    /// Inactive navigation icon — Catchlight @ 55% (Night) / Fog (Daylight).
    static let ckNavInactive = Color(SceneColor(\.muted))

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
    static let ckAccent = Color(SceneColor(\.accentText))

    /// Foreground drawn ON an Ember fill (the Add "+", active filter glyphs):
    /// Ink in BOTH modes. Night was already Ink-coloured (it used `ckBackground`
    /// = Ink), so this is unchanged there; in Daylight it replaces Paper-on-Ember
    /// (2.04:1, fails) with Ink-on-Ember (8.62:1). Use for amber-filled chrome
    /// controls. NOTE: the locked primary CTAs (DockPill, Paywall) are a
    /// separate owner call (see audit C4) and are NOT switched here.
    static let ckOnAccent = Color(SceneColor(\.onAccent))

    /// The veil — the ONE obscuring overlay for the Focus row, the editor, and the
    /// Settings backdrop (owner decision 2026-06-11: solid 90% background veil
    /// everywhere; no blur, no dark tint in Daylight). Ink @ 90% (Night) /
    /// Paper @ 90% (Daylight). The screens beneath stay full-opacity — the
    /// veil alone provides the recede.
    static let ckDim = Color(SceneColor(\.ground, opacity: 0.90))

    // MARK: - Take card variants (HiFi v1.7 .card — section 5)
    //
    // The Take card surface is `ckSurface` (White Daylight / Dusk Night). These
    // tokens cover the two variant treatments v1.7 layers on top. Added 2026-06-14
    // (fix pass 1).

    /// Obie card BACKGROUND — a warm tint distinct from the plain surface so the
    /// pinned Take reads as special. Daylight #FBF8F3 (Ember @8% blended onto
    /// White, solid to prevent spine bleed) / Night #2D2921. (HiFi v1.7 .obie-card)
    static let ckCardObieSurface = Color(SceneColor(\.raised))

    /// Obie card BORDER — Ember @65% (Daylight) / Glow @65% (Night). The Ember
    /// border is reserved EXCLUSIVELY for the Obie. (HiFi v1.7 .obie-card)
    static let ckCardObieBorder = Color(SceneColor(\.lit))

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
    static let ckCardDoneBorder = Color(SceneColor(\.faint))

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

// MARK: - Flat shapes (redesign)
//
// Every surface the app draws is flat: no shadows, gradients or raised materials. Buttons
// and toggles are rounded rectangles at `CatchlightLayout.controlRadius`, and fields, panels
// and cards are rounded rectangles at `CatchlightLayout.surfaceRadius`. Never a pill.

enum CatchlightShape {
    /// Buttons, toggles and the marks inside them.
    static let control = RoundedRectangle(cornerRadius: CatchlightLayout.controlRadius, style: .continuous)
    /// Fields, panels, cards and sheets.
    static let surface = RoundedRectangle(cornerRadius: CatchlightLayout.surfaceRadius, style: .continuous)
}

extension View {
    /// A field's flat surface: the card colour, a 1pt outline from the `outline` token (3:1
    /// on every surface) and the surface radius.
    func flatField(fill: Color = .ckSurface) -> some View {
        background(CatchlightShape.surface.fill(fill))
            .overlay(CatchlightShape.surface.strokeBorder(Color.ckOutline, lineWidth: 1))
    }

    /// A panel's flat surface: the card colour and a hairline edge from the `line` token.
    func flatPanel(fill: Color = .ckSurface) -> some View {
        background(CatchlightShape.surface.fill(fill))
            .overlay(CatchlightShape.surface.strokeBorder(Color.ckLine, lineWidth: 1))
    }
}

/// The measurements of the flat toggle, stated once so a test can hold them. The knob is
/// concentric with the track: its corner radius is the control radius less the inset.
enum FlatToggleMetrics {
    static let trackWidth: CGFloat = 46
    static let trackHeight: CGFloat = 28
    static let knobInset: CGFloat = 3
    static var knobSize: CGFloat { trackHeight - knobInset * 2 }
    static var knobRadius: CGFloat { CatchlightLayout.controlRadius - knobInset }
    /// The tap target around the track: at least 44 by 44.
    static var tapTarget: CGSize {
        CGSize(width: max(trackWidth, CatchlightLayout.minTouchTarget),
               height: max(trackHeight, CatchlightLayout.minTouchTarget))
    }
}

/// A toggle drawn as a rounded rectangle track with a rounded square knob, never a pill.
/// Off is the `outline` edge on the card (3:1), on is the chosen fill. Only the track takes
/// a tap (in a 44 by 44 target) or a horizontal drag, as the native switch does, and the label
/// does not. VoiceOver and XCUITest see the native switch: the accessibility representation
/// is a real `Toggle`.
struct FlatToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            FlatToggleTrack(isOn: configuration.$isOn)
        }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}

private struct FlatToggleTrack: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let knob = FlatToggleMetrics.knobSize
        let inset = FlatToggleMetrics.knobInset
        ZStack(alignment: isOn ? .trailing : .leading) {
            CatchlightShape.control
                .fill(fill)
            CatchlightShape.control
                .strokeBorder(edge, lineWidth: 1.5)
            RoundedRectangle(cornerRadius: FlatToggleMetrics.knobRadius, style: .continuous)
                .fill(knobColour)
                .frame(width: knob, height: knob)
                .padding(inset)
        }
        .frame(width: FlatToggleMetrics.trackWidth, height: FlatToggleMetrics.trackHeight)
        .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: isOn)
        .frame(width: FlatToggleMetrics.tapTarget.width, height: FlatToggleMetrics.tapTarget.height)
        .contentShape(Rectangle())
        .onTapGesture { if isEnabled { isOn.toggle() } }
        .gesture(
            DragGesture(minimumDistance: 10).onEnded { drag in
                guard isEnabled, abs(drag.translation.width) > abs(drag.translation.height) else { return }
                let towardTrailing = layoutDirection == .leftToRight
                    ? drag.translation.width > 0 : drag.translation.width < 0
                isOn = towardTrailing
            }
        )
    }

    private var fill: Color {
        guard isEnabled else { return .ckDisabledFill }
        return isOn ? .ckChosenFill : .ckSurface
    }
    private var edge: Color {
        guard isEnabled else { return .ckDisabledFill }
        return isOn ? .ckChosenFill : .ckOutline
    }
    private var knobColour: Color {
        guard isEnabled else { return .ckDisabledLabel }
        return isOn ? .ckChosenMark : .ckOutline
    }
}

/// The measurements of the flat segmented control. The selected segment is concentric with
/// the container: its corner radius is the control radius less the inset.
enum FlatSegmentedMetrics {
    static let inset: CGFloat = 3
    static var selectedRadius: CGFloat { CatchlightLayout.controlRadius - inset }
    static let segmentHeight: CGFloat = CatchlightLayout.minTouchTarget
}

/// A two or more segment choice drawn as a rounded rectangle at the control radius, never a
/// capsule. Each segment is a button of at least 44pt with the selected trait on the chosen
/// one. The chosen segment is the chosen fill with the chosen mark.
struct FlatSegmentedControl<Value: Hashable>: View {
    let label: String
    let segments: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments.indices, id: \.self) { index in
                let segment = segments[index]
                let selected = segment.value == selection
                Button {
                    selection = segment.value
                } label: {
                    Text(segment.title)
                        .ckBody(.medium, size: 15, relativeTo: .body)
                        .foregroundStyle(selected ? Color.ckChosenMark : Color.ckTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: FlatSegmentedMetrics.segmentHeight)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: FlatSegmentedMetrics.selectedRadius, style: .continuous)
                                    .fill(Color.ckChosenFill)
                                    .padding(FlatSegmentedMetrics.inset)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .background(CatchlightShape.control.fill(Color.ckSurface))
        .overlay(CatchlightShape.control.strokeBorder(Color.ckOutline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// The face of a filled action button: the action colour with its on-colour label, or the
/// disabled pair while the button is disabled (read from the environment, so the button
/// needs no flag). A rounded rectangle at the control radius, never a pill.
private struct FlatPrimaryFace: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    func body(content: Content) -> some View {
        content
            .foregroundStyle(isEnabled ? Color.ckOnAccent : Color.ckDisabledLabel)
            .background(CatchlightShape.control.fill(isEnabled ? Color.ckAdd : Color.ckDisabledFill))
            .contentShape(CatchlightShape.control)
    }
}

extension View {
    func flatPrimaryFace() -> some View { modifier(FlatPrimaryFace()) }
}

extension UITheme {
    /// What a chosen state is drawn in: the on track of a toggle and the selected segment.
    /// The text-grade accent: the raw accent is a yellow in Graphite Light and is 1.45:1 there.
    static let chosenFill = SceneToken.accentText
    /// The knob or label on a chosen fill: the card colour, which stays readable on the
    /// text-grade accent in every Scene (the on-accent colour is nearly the same dark there).
    static let chosenMark = SceneToken.card
    /// A disabled button's fill and label. The label reaches 3:1 on the fill in every Scene
    /// (`SceneContrastTests`): the old way faded the whole button, and a faded label on a
    /// faded fill was pale on pale.
    static let disabledFill  = SceneToken.line
    static let disabledLabel = SceneToken.muted
}

extension Color {
    static let ckChosenFill = Color(uiColor: UITheme.chosenFill)
    static let ckChosenMark = Color(uiColor: UITheme.chosenMark)
    static let ckDisabledFill = Color(SceneColor(\.line))
    static let ckDisabledLabel = Color(SceneColor(\.muted))
}

// MARK: - Typography

enum CatchlightFont {
    // Headings and display text are Archivo, set expanded. Body text is the system
    // font. Archivo is bundled as one variable TTF,
    // `Catchlight/Resources/Fonts/Archivo.ttf`, registered in `Info.plist`
    // (UIAppFonts).
    //
    // Axes (read from the file's `fvar` table with fontTools):
    //   wght  100 to 900, default 600
    //   wdth   62 to 125, default 100
    // Names (name table): family "Archivo", default instance PostScript name
    // "Archivo-SemiBold". The named instances (ArchivoRoman-Regular and the rest) are
    // all at wdth 100 and do not resolve through `UIFont(name:)`, so every heading
    // starts from the default instance and sets both axes through
    // `kCTFontVariationAttribute`.
    //
    // Live Dynamic Type: a SwiftUI `Font` made from a UIFont is fixed, so the text
    // styles below (`ckBody`, `ckDisplay`) read the view's `dynamicTypeSize` and build
    // the font for it. The fonts themselves are cached, so nothing is built per render.
    private static let archivoCandidates = ["Archivo-SemiBold", "Archivo"]

    static let headingWeight: CGFloat = HeadingAxes.weight
    static let headingWidth: CGFloat = HeadingAxes.width

    /// Line spacing for a heading that can wrap: Archivo's natural line is 1.088 em
    /// (hhea ascent 878, descent 210), so about 0.09 em off lands on 1.0 em.
    static func tightLeading(size: CGFloat) -> CGFloat { -size * 0.09 }

    // MARK: Caches

    /// One lock and one table for every font built here. The key names what the font
    /// depends on, so a font is built once per size, weight, width, language and
    /// content size, and never per render.
    private static var cache: [String: UIFont] = [:]
    private static var resolvedNames: [String: String?] = [:]
    private static let lock = NSLock()

    private static var builds = 0
    private static var cachingOff = false

    private static func cached(_ key: String, _ build: () -> UIFont) -> UIFont {
        lock.lock()
        if !cachingOff, let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        let made = build()
        lock.lock()
        builds += 1
        if !cachingOff { cache[key] = made }
        lock.unlock()
        return made
    }

    /// How many fonts have been built since launch. The tests read it to prove repeat
    /// calls build nothing.
    static var fontBuildCount: Int {
        lock.lock(); defer { lock.unlock() }
        return builds
    }

    /// Test hook: with caching off every call builds, which is what the build counter
    /// must be able to see.
    static func setCachingDisabledForTests(_ off: Bool) {
        lock.lock(); cachingOff = off; lock.unlock()
    }

    private static func firstAvailable(_ names: [String]) -> String? {
        let key = names.joined(separator: "|")
        lock.lock()
        defer { lock.unlock() }
        if let cached = resolvedNames[key] { return cached }
        let resolved = names.first { UIFont(name: $0, size: 12) != nil }
        resolvedNames[key] = resolved
        return resolved
    }

    // MARK: UIFont builders

    /// Archivo at `size`, with the weight and width axes set. Falls back to the system
    /// font at medium weight when the bundled face is not registered.
    static func archivo(size: CGFloat, weight: CGFloat, width: CGFloat) -> UIFont {
        cached("archivo|\(size)|\(weight)|\(width)") {
            guard let name = firstAvailable(archivoCandidates) else {
                return UIFont.systemFont(ofSize: size, weight: .medium)
            }
            let variation: [Int: CGFloat] = [HeadingAxes.weightTag: weight, HeadingAxes.widthTag: width]
            let descriptor = UIFontDescriptor(fontAttributes: [
                .name: name,
                .size: size,
                UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variation
            ])
            return UIFont(descriptor: descriptor, size: size)
        }
    }

    /// The system sans the display text falls back to for characters Archivo has no
    /// glyph for, by app language, at a medium weight to sit beside the heading.
    /// Archivo covers Latin scripts only. Japanese takes Hiragino Sans, Chinese takes
    /// PingFang in its regional cut and Korean takes Apple SD Gothic Neo. Every other
    /// language keeps iOS's own fallback, which is a sans.
    static func displayFallback(for language: String?) -> String? {
        guard let language else { return nil }
        if language.hasPrefix("ja") { return "HiraginoSans-W5" }
        if language.hasPrefix("ko") { return "AppleSDGothicNeo-Medium" }
        if language.hasPrefix("zh") {
            if language.contains("HK") || language.contains("MO") { return "PingFangHK-Medium" }
            if language.contains("Hant") || language.hasSuffix("TW") { return "PingFangTC-Medium" }
            return "PingFangSC-Medium"
        }
        return nil
    }

    static var appLanguage: String? { Bundle.main.preferredLocalizations.first }

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

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }

    /// The unscaled heading font for `language`, with the language's fallback in its
    /// cascade list.
    private static func displayBase(size: CGFloat, language: String?) -> UIFont {
        cached("display|\(size)|\(language ?? "-")") {
            let archivo = archivo(size: size, weight: headingWeight, width: headingWidth)
            guard let name = displayFallback(for: language) else { return archivo }
            let cascade = [UIFontDescriptor(name: name, size: size)]
            let descriptor = archivo.fontDescriptor.addingAttributes([.cascadeList: cascade])
            return UIFont(descriptor: descriptor, size: size)
        }
    }

    /// Heading / display face as a UIFont: Archivo, expanded, upright. With a `style`
    /// it scales with Dynamic Type relative to that style, with nil it stays at `size`.
    /// `traits` names the content size to scale for, and nil means the current one.
    static func uiDisplay(size: CGFloat,
                          relativeTo style: Font.TextStyle? = .body,
                          compatibleWith traits: UITraitCollection? = nil,
                          language: String? = CatchlightFont.appLanguage) -> UIFont {
        let base = displayBase(size: size, language: language)
        guard let style else { return base }
        let metrics = UIFontMetrics(forTextStyle: uiTextStyle(style))
        guard let traits else { return metrics.scaledFont(for: base) }
        let key = "displayScaled|\(size)|\(language ?? "-")|\(style)|\(traits.preferredContentSizeCategory.rawValue)"
        return cached(key) { metrics.scaledFont(for: base, compatibleWith: traits) }
    }

    /// Body face as a UIFont: the system font at `weight`, scaled with Dynamic Type
    /// relative to `style`. For `UIViewRepresentable` text surfaces (the block
    /// editor's `UITextView` rows) and the keyboard bars.
    static func uiBody(size: CGFloat,
                       weight: Font.Weight = .regular,
                       relativeTo style: Font.TextStyle = .body,
                       compatibleWith traits: UITraitCollection? = nil) -> UIFont {
        let metrics = UIFontMetrics(forTextStyle: uiTextStyle(style))
        let base = cached("system|\(size)|\(weight)") { UIFont.systemFont(ofSize: size, weight: uiWeight(weight)) }
        guard let traits else { return metrics.scaledFont(for: base) }
        let key = "systemScaled|\(size)|\(weight)|\(style)|\(traits.preferredContentSizeCategory.rawValue)"
        return cached(key) { metrics.scaledFont(for: base, compatibleWith: traits) }
    }

    /// `size` scaled for a content size and text style, the point size a body font
    /// takes at that size.
    static func scaledPoints(_ size: CGFloat, relativeTo style: Font.TextStyle,
                             compatibleWith traits: UITraitCollection) -> CGFloat {
        UIFontMetrics(forTextStyle: uiTextStyle(style)).scaledValue(for: size, compatibleWith: traits)
    }

    /// The UIKit content size category for a SwiftUI Dynamic Type size.
    static func contentSizeCategory(_ size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

// MARK: - Text styles

/// Interface text. The font is rebuilt from the view's own Dynamic Type size, so it
/// grows while the screen is open. It is a SwiftUI system font at the scaled size.
/// Markdown emphasis needs `EmphasisText`: SwiftUI steps a light font's weight up by
/// one for emphasis, which is not visibly bold.
private struct BodyFontModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let weight: Font.Weight
    let size: CGFloat
    let style: Font.TextStyle

    func body(content: Content) -> some View {
        let traits = UITraitCollection(preferredContentSizeCategory: CatchlightFont.contentSizeCategory(dynamicTypeSize))
        return content.font(.system(size: CatchlightFont.scaledPoints(size, relativeTo: style, compatibleWith: traits),
                                    weight: weight))
    }
}

/// Heading and display text in Archivo, expanded. A nil `style` keeps the size fixed.
private struct DisplayFontModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let size: CGFloat
    let style: Font.TextStyle?

    func body(content: Content) -> some View {
        let traits = UITraitCollection(preferredContentSizeCategory: CatchlightFont.contentSizeCategory(dynamicTypeSize))
        return content.font(Font(CatchlightFont.uiDisplay(size: size, relativeTo: style, compatibleWith: traits)))
    }
}

/// A sentence with inline Markdown emphasis (`**word**`) in the body font, the emphasised
/// words in bold, scaling live with Dynamic Type. The Markdown stays in the string, so a
/// translation can move the emphasis to wherever its own word order puts it.
struct EmphasisText: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let source: String
    private let weight: Font.Weight
    private let size: CGFloat
    private let style: Font.TextStyle

    init(_ key: LocalizedStringResource, _ weight: Font.Weight = .regular, size: CGFloat, relativeTo style: Font.TextStyle = .body) {
        self.source = String(localized: key)
        self.weight = weight
        self.size = size
        self.style = style
    }

    var body: some View {
        let traits = UITraitCollection(preferredContentSizeCategory: CatchlightFont.contentSizeCategory(dynamicTypeSize))
        let points = CatchlightFont.scaledPoints(size, relativeTo: style, compatibleWith: traits)
        var text = (try? AttributedString(markdown: source,
                                          options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(source)
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            text[run.range].font = .system(size: points, weight: .bold)
            text[run.range].inlinePresentationIntent = nil
        }
        return Text(text).font(.system(size: points, weight: weight))
    }
}

extension View {
    /// Interface text: the system font, scaling live with Dynamic Type relative to `style`.
    func ckBody(_ weight: Font.Weight = .regular, size: CGFloat, relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(BodyFontModifier(weight: weight, size: size, style: style))
    }

    /// Heading text: Archivo expanded. Pass a `style` to scale live with Dynamic Type, or
    /// nil for the brand display that stays at a fixed size (onboarding heroes, the
    /// Obie title treatment, BIP-39 word chips). Take content is never the display face.
    func ckDisplay(size: CGFloat, relativeTo style: Font.TextStyle?) -> some View {
        modifier(DisplayFontModifier(size: size, style: style))
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
    /// Corner radius of a button or toggle. Never a pill.
    static let controlRadius: CGFloat = 10
    /// Corner radius of a field, panel, card or sheet.
    static let surfaceRadius: CGFloat = 16
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
    /// Leading inset `PageHeading` adds to optically centre the kerned title.
    /// `.kerning` adds trailing space after the last glyph (~half a glyph more than
    /// the kern value itself), pulling a plainly-centred title left; 3.0 lands the
    /// ink dead-centre — measured on DAILIES, 601→603px (owner 2026-06-29).
    static let pageHeadingKerningComp: CGFloat = 3.0
}

/// The page heading: Archivo expanded 24, kerned, centred, `ckTextPrimary`. Shared by
/// every screen's heading so they can't drift. A one-word title stays on one line and
/// scales down to fit. A title of several words wraps between words onto two balanced
/// lines when one line is too wide, and only scales down when a single word still does
/// not fit. Nothing breaks inside a word.
///
/// `.kerning` adds its spacing AFTER the last glyph too, so a plainly-centred kerned
/// title sits about half a kern left of true centre. The matching leading padding
/// cancels that trailing space so the letters read dead-centre (owner 2026-06-29).
struct PageHeading: View {
    let title: String

    init(_ title: LocalizedStringResource) { self.title = String(localized: title) }
    init(verbatim title: String) { self.title = title }

    /// `title` split onto two lines at a word boundary, the split that makes the longer
    /// line shortest. Nil for a one-word title.
    static func twoLines(_ title: String) -> String? {
        let words = title.split(separator: " ").map(String.init)
        guard words.count > 1 else { return nil }
        var best: (Int, Int)?
        for k in 1..<words.count {
            let longest = max(words[..<k].joined(separator: " ").count, words[k...].joined(separator: " ").count)
            if best == nil || longest < best!.1 { best = (k, longest) }
        }
        let k = best!.0
        return words[..<k].joined(separator: " ") + "\n" + words[k...].joined(separator: " ")
    }

    /// The soft hyphen a translation puts at a true compound join, so a word that is too
    /// long for the line can break there with a hyphen.
    static let softHyphen = "\u{00AD}"

    /// What a heading draws: the text (newlines where it breaks, with a hyphen at a soft
    /// hyphen break), the point size, and whether it broke at soft hyphens.
    struct Fit: Equatable {
        var text: String
        var points: CGFloat
        var wraps: Bool
    }

    /// How a heading fits `width` at `category`: one line, then two balanced lines at a
    /// word boundary, then shrinking to fit, but never below the body text size at that
    /// Dynamic Type size. Past that floor a word breaks at a soft hyphen, and a title with
    /// no soft hyphen that still does not fit keeps shrinking, so nothing is cut and
    /// nothing breaks inside a word. The floor can give way only when even half a
    /// compound, at the body size, is wider than the line.
    static func fit(_ title: String, width: CGFloat, category: UIContentSizeCategory,
                    language: String? = CatchlightFont.appLanguage) -> Fit {
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let font = CatchlightFont.uiDisplay(size: 24, relativeTo: .title3, compatibleWith: traits, language: language)
        let full = font.pointSize
        let bodyPoints = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits).pointSize
        let floorScale = min(1, bodyPoints / full)
        let available = width - CatchlightLayout.pageHeadingKerningComp - 1

        // The kerning is a fixed number of points per character and does not shrink with
        // the font, so a line at scale `s` is `glyphs * s + kern * characters` wide.
        func glyphs(_ line: String) -> CGFloat {
            (line as NSString).size(withAttributes: [.font: font]).width
        }
        func kern(_ line: String) -> CGFloat { CatchlightLayout.pageHeadingKerning * CGFloat(line.count) }
        func lineWidth(_ line: String, scale: CGFloat) -> CGFloat { glyphs(line) * scale + kern(line) }
        func widest(_ text: String, scale: CGFloat) -> CGFloat {
            text.components(separatedBy: "\n").map { lineWidth($0, scale: scale) }.max() ?? 0
        }
        /// The largest scale at which every line of `text` fits.
        func scaleToFit(_ text: String) -> CGFloat {
            text.components(separatedBy: "\n").map { (available - kern($0)) / glyphs($0) }.min() ?? 1
        }

        let plain = title.replacingOccurrences(of: softHyphen, with: "")
        if widest(plain, scale: 1) <= available { return Fit(text: plain, points: full, wraps: false) }
        let two = twoLines(plain)
        if let two, widest(two, scale: 1) <= available { return Fit(text: two, points: full, wraps: false) }

        let shrinkable = two ?? plain
        let need = scaleToFit(shrinkable)
        if need >= floorScale { return Fit(text: shrinkable, points: full * need, wraps: false) }

        // Past the floor, a title with a soft hyphen breaks there (and at spaces). It draws
        // at the floor size, or smaller only when even its longest piece, with its hyphen,
        // does not fit the width at that size.
        if title.contains(softHyphen) {
            // Units are the pieces between spaces and soft hyphens. The lines are broken here,
            // not by Text, which would also hyphenate inside a piece.
            var units: [(text: String, boundary: Character)] = []
            for (w, word) in title.components(separatedBy: " ").enumerated() {
                let parts = word.components(separatedBy: softHyphen)
                for (i, part) in parts.enumerated() {
                    let last = i == parts.count - 1
                    units.append((part, !last ? "-" : (w == title.components(separatedBy: " ").count - 1 ? "." : " ")))
                }
            }
            func hyphenated(_ u: (text: String, boundary: Character)) -> String { u.text + (u.boundary == "-" ? "-" : "") }
            let pieceFit = units.map { (available - kern(hyphenated($0))) / glyphs(hyphenated($0)) }.min() ?? 1
            let scale = min(floorScale, pieceFit)
            var lines: [String] = []
            var current = ""
            var previous: Character = " "
            for u in units {
                let glue = current.isEmpty ? "" : (previous == " " ? " " : "")
                let candidate = current + glue + u.text
                if current.isEmpty || lineWidth(candidate + (u.boundary == "-" ? "-" : ""), scale: scale) <= available {
                    current = candidate
                } else {
                    lines.append(current + (previous == "-" ? "-" : ""))
                    current = u.text
                }
                previous = u.boundary
            }
            lines.append(current)
            return Fit(text: lines.joined(separator: "\n"), points: full * scale, wraps: true)
        }
        return Fit(text: shrinkable, points: full * max(need, 0.05), wraps: false)
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var width: CGFloat = 0

    var body: some View {
        let category = CatchlightFont.contentSizeCategory(dynamicTypeSize)
        let fit = width > 0 ? Self.fit(title, width: width, category: category) : nil
        Text(fit?.text ?? title.replacingOccurrences(of: Self.softHyphen, with: ""))
            .ckDisplay(size: fit?.points ?? 24, relativeTo: fit == nil ? .title3 : nil)
            .lineLimit(fit.map { $0.text.components(separatedBy: "\n").count } ?? 1)
            .multilineTextAlignment(.center)
            .kerning(CatchlightLayout.pageHeadingKerning)
            .foregroundStyle(Color.ckTextPrimary)
            .padding(.leading, CatchlightLayout.pageHeadingKerningComp)
            .fixedSize(horizontal: true, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .accessibilityLabel(title.replacingOccurrences(of: Self.softHyphen, with: ""))
    }
}
