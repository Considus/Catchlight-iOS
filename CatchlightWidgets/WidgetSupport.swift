//
//  WidgetSupport.swift
//  CatchlightWidgets: shared colours, provider and views
//
//  All Catchlight widgets are LAUNCHERS: a single static entry, no timeline
//  refresh, no Take content. They render the brand and a deep link; tapping
//  opens the app to capture. Because nothing is decrypted or displayed, the
//  keychain wall is irrelevant here (owner 2026-06-22, Ideas Backlog §7).
//
//  Take and Obie widgets share these views, parameterised by `CaptureSurface`
//  (owner 2026-06-23: every Take widget has an Obie twin).
//
//  The redesign (spec R17, R18; drawn in catchlight-icon-and-widgets.html):
//   • The Iris is the brand symbol, drawn from `IrisGeometry`, which the app shares:
//     New Take is the Iris with its Note light lit and the Note shape. On the Home
//     Screen, New Obie is an Obie made from a note: Important and Note lit, the inner
//     square and the Note lines. The round Lock Screen widget and the controls show
//     the control symbol instead: the outline with a plus, or with the inner square.
//   • Colours are the chosen Scene's, read from the app group at each render, in
//     Night or Daylight with the system appearance. The app reloads the widgets when
//     the Scene changes (`SettingsViewModel.SceneChoice.select`).
//   • Each view reads `widgetRenderingMode`. Full colour draws the Scene; accented
//     (tinted and clear Home Screens) and vibrant (Lock Screen, StandBy at night) draw
//     one colour, with the lit light, the Obie's inner square and the plus button
//     marked accentable. Backgrounds go through `containerBackground`, so the system
//     can remove them (StandBy, accented).
//   • System font only, 12pt and up. Flat: no shadows or gradients.
//

import WidgetKit
import SwiftUI
import CatchlightCore

// MARK: - Scene colours

private extension UIColor {
    convenience init(rgbHex hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

/// The chosen Scene's colours, Night or Daylight by the system appearance. Computed on
/// every read, never cached: the extension's process can outlive a Scene change.
enum WidgetPalette {
    static func color(_ role: KeyPath<ScenePalette, UInt32>, opacity: CGFloat = 1) -> Color {
        let scene = CatchlightScene.stored()
        return Color(uiColor: UIColor { traits in
            let hex = scene.palette(dark: traits.userInterfaceStyle == .dark)[keyPath: role]
            return UIColor(rgbHex: hex, alpha: opacity)
        })
    }

    static var surface: Color { color(\.surface) }
    static var card: Color { color(\.card) }
    static var raised: Color { color(\.raised) }
    static var line: Color { color(\.line) }
    static var text: Color { color(\.text) }
    static var muted: Color { color(\.muted) }
    static var accent: Color { color(\.accent) }
    static var onAccent: Color { color(\.onAccent) }
    static var lit: Color { color(\.lit) }
    /// An unlit light in full colour: `muted` at 78%, as drawn.
    static var unlitLight: Color { color(\.muted, opacity: 0.78) }
}

// MARK: - Text

private struct WidgetUIFontModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let size: CGFloat
    let weight: Font.Weight

    func body(content: Content) -> some View {
        let category: UIContentSizeCategory
        switch dynamicTypeSize {
        case .xSmall: category = .extraSmall
        case .small: category = .small
        case .medium: category = .medium
        case .large: category = .large
        case .xLarge: category = .extraLarge
        case .xxLarge: category = .extraExtraLarge
        case .xxxLarge: category = .extraExtraExtraLarge
        case .accessibility1: category = .accessibilityMedium
        case .accessibility2: category = .accessibilityLarge
        case .accessibility3: category = .accessibilityExtraLarge
        case .accessibility4: category = .accessibilityExtraExtraLarge
        case .accessibility5: category = .accessibilityExtraExtraExtraLarge
        @unknown default: category = .large
        }
        let points = UIFontMetrics(forTextStyle: .body)
            .scaledValue(for: size, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
        return content.font(.system(size: points, weight: weight))
    }
}

extension View {
    /// Widget text: the system font, scaling live with Dynamic Type.
    func widgetUI(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(WidgetUIFontModifier(size: size, weight: weight))
    }
}

/// A title and its line beneath, coloured for the rendering mode.
struct WidgetTitle: View {
    let title: String
    let subtitle: String
    var titleSize: CGFloat = 17
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .widgetUI(titleSize, weight: .semibold)
                .foregroundStyle(mode == .fullColor ? WidgetPalette.text : Color.primary)
            Text(subtitle)
                .widgetUI(12)
                .foregroundStyle(mode == .fullColor ? WidgetPalette.muted : Color.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

// MARK: - Capture surface (Take vs Obie)

/// What one launcher or card shows and where it goes.
struct CaptureSurface {
    let url: URL
    let title: String        // "New Take" / "New Obie"
    let shortTitle: String   // "Take" / "Obie", for each half of the two-in-one widget
    let subtitle: String     // the line under the title
    let isObie: Bool

    static let take = CaptureSurface(
        url: CaptureRouting.captureURL(.text),
        title: String(localized: "New Take"),
        shortTitle: String(localized: "Take"),
        subtitle: String(localized: "Tap to write"),
        isObie: false
    )

    static let obie = CaptureSurface(
        url: CaptureRouting.captureURL(.obie),
        title: String(localized: "New Obie"),
        shortTitle: String(localized: "Obie"),
        subtitle: String(localized: "Tap to start"),
        isObie: true
    )
}

// MARK: - The Iris

/// One part of the Iris, scaled from its 44-unit space to the frame.
private struct IrisPart: Shape {
    let path: @Sendable (CGFloat) -> Path
    func path(in rect: CGRect) -> Path { path(min(rect.width, rect.height) / 44) }
}

/// The brand Iris: New Take lights Note and shows the Note shape, New Obie shows the
/// inner square. Built from separate layers so the lit light and the inner square can
/// be accentable while the unlit lights are not.
struct WidgetIris: View {
    let surface: CaptureSurface
    let size: CGFloat
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.widgetFamily) private var family

    /// On the Home Screen, New Obie shows a new Obie as the app draws one made from a
    /// note: Important and Note lit, the inner square and the Note lines (Mark,
    /// 2026-11-10). The Lock Screen keeps the inner square alone.
    private var obieAsInApp: Bool {
        surface.isObie && ![.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family)
    }

    var body: some View {
        let s = size / 44
        let full = mode == .fullColor
        let lit: Set<IrisLight> = surface.isObie ? (obieAsInApp ? [.important, .note] : []) : [.note]
        ZStack {
            IrisPart { IrisGeometry.lights(Set(IrisLight.allCases).subtracting(lit), scale: $0) }
                .stroke(full ? WidgetPalette.unlitLight : Color.white.opacity(0.4),
                        style: StrokeStyle(lineWidth: IrisGeometry.unlitWidth * s, lineCap: .round))
            if surface.isObie {
                if !lit.isEmpty {
                    IrisPart { IrisGeometry.lights(lit, scale: $0) }
                        .stroke(full ? WidgetPalette.lit : Color.white,
                                style: StrokeStyle(lineWidth: IrisGeometry.litWidth * s, lineCap: .round))
                        .widgetAccentable()
                }
                IrisPart { IrisGeometry.obieSquare(scale: $0) }
                    .stroke(full ? WidgetPalette.lit : Color.white,
                            lineWidth: IrisGeometry.obieSquareWidth * s)
                    .widgetAccentable()
                if obieAsInApp {
                    IrisPart { IrisGeometry.innerPath(.note, scale: $0) }
                        .stroke(full ? WidgetPalette.text : Color.white.opacity(0.88),
                                style: StrokeStyle(lineWidth: IrisGeometry.innerWidth(.note) * s,
                                                   lineCap: .round, lineJoin: .round))
                }
            } else {
                IrisPart { IrisGeometry.lights(lit, scale: $0) }
                    .stroke(full ? WidgetPalette.lit : Color.white,
                            style: StrokeStyle(lineWidth: IrisGeometry.litWidth * s, lineCap: .round))
                    .widgetAccentable()
                IrisPart { IrisGeometry.innerPath(.note, scale: $0) }
                    .stroke(full ? WidgetPalette.text : Color.white.opacity(0.88),
                            style: StrokeStyle(lineWidth: IrisGeometry.innerWidth(.note) * s,
                                               lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - The round Lock Screen symbol

/// The control symbol drawn for the round Lock Screen widget (Art Director, 2026-11-10):
/// the Iris outline in its six lights, with a plus inside for New Take and the inner
/// square for New Obie. One idea per widget, like the system's round widgets: no badge,
/// no Note lines. The outline's box is 56% of the circle, its line 1.5pt to match the
/// system's widget text beside it; the plus or the square takes the tint.
struct RoundLockScreenSymbol: View {
    let surface: CaptureSurface

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.56
            let line = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            ZStack {
                IrisPart { IrisGeometry.lights(Set(IrisLight.allCases), scale: $0) }
                    .stroke(Color.white, style: line)
                if surface.isObie {
                    IrisPart { IrisGeometry.obieSquare(scale: $0) }
                        .stroke(Color.white, style: line)
                        .widgetAccentable()
                } else {
                    // Arms reach 45% of the outline's inner width, centred on the Iris.
                    IrisPart { s in
                        let half = 41 * 0.45 / 2
                        var p = Path()
                        p.move(to: CGPoint(x: 22 * s, y: (22 - half) * s))
                        p.addLine(to: CGPoint(x: 22 * s, y: (22 + half) * s))
                        p.move(to: CGPoint(x: (22 - half) * s, y: 22 * s))
                        p.addLine(to: CGPoint(x: (22 + half) * s, y: 22 * s))
                        return p
                    }
                    .stroke(Color.white, style: line)
                    .widgetAccentable()
                }
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

// MARK: - The plus button

/// The one action: a rounded square with a plus. Full colour is the Scene accent with the
/// plus in `onAccent`; the one-colour modes cut the plus out, so it reads in any tint.
struct WidgetPlus: View {
    let size: CGFloat
    let radius: CGFloat
    let glyph: CGFloat
    @Environment(\.widgetRenderingMode) private var mode

    private var plus: some Shape {
        IrisPart { s in
            // The drawing's plus: M8 3v10 M3 8h10 in a 16 grid. `s` is per 44 units.
            let u = s * 44 / 16
            var p = Path()
            p.move(to: CGPoint(x: 8 * u, y: 3 * u)); p.addLine(to: CGPoint(x: 8 * u, y: 13 * u))
            p.move(to: CGPoint(x: 3 * u, y: 8 * u)); p.addLine(to: CGPoint(x: 13 * u, y: 8 * u))
            return p
        }
        .stroke(style: StrokeStyle(lineWidth: 2.2 * glyph / 16, lineCap: .round))
    }

    var body: some View {
        if mode == .fullColor {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(WidgetPalette.accent)
                .overlay { plus.foregroundStyle(WidgetPalette.onAccent).frame(width: glyph, height: glyph) }
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.white)
                .overlay { plus.frame(width: glyph, height: glyph).blendMode(.destinationOut) }
                .compositingGroup()
                .frame(width: size, height: size)
                .widgetAccentable()
        }
    }
}

// MARK: - Cards inside the medium widgets

extension View {
    /// The card a medium widget's content sits on: 11pt in from the edge, an 11pt corner,
    /// the Scene's `raised` colour with a 1pt `line` border. Flat, never a shadow.
    func widgetCard() -> some View { modifier(WidgetCardModifier()) }

    /// The widget's background, through `containerBackground` so the system can remove
    /// it: the Scene colour for Home Screen sizes, the system's own on the Lock Screen.
    func widgetBackground(_ fill: @escaping () -> Color) -> some View {
        modifier(WidgetBackgroundModifier(fill: fill))
    }
}

private struct WidgetCardModifier: ViewModifier {
    @Environment(\.widgetRenderingMode) private var mode

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let full = mode == .fullColor
        return content
            .background { shape.fill(full ? WidgetPalette.raised : Color.white.opacity(0.07)) }
            .overlay { shape.strokeBorder(full ? WidgetPalette.line : Color.white.opacity(0.22), lineWidth: 1) }
    }
}

private struct WidgetBackgroundModifier: ViewModifier {
    let fill: () -> Color
    @Environment(\.widgetFamily) private var family

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            switch family {
            case .accessoryCircular, .accessoryRectangular, .accessoryInline:
                AccessoryWidgetBackground()
            default:
                fill()
            }
        }
    }
}

// MARK: - Static launcher timeline

struct LauncherEntry: TimelineEntry {
    let date: Date
}

/// One fixed entry; launchers never need to refresh (`.never`). The app reloads them
/// when the Scene changes.
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

/// The small Home Screen launcher and the two Lock Screen ones, for one surface.
struct LauncherView: View {
    let surface: CaptureSurface
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            // The system's filled circle, drawn in the content: the Lock Screen removes a
            // container background, so it would not show from there (Mark's screenshot,
            // 2026-11-10). The symbol sits centred in it, like the system's own round widgets.
            ZStack {
                AccessoryWidgetBackground()
                RoundLockScreenSymbol(surface: surface)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(surface.title)
        case .accessoryRectangular:
            HStack(spacing: 10) {
                WidgetIris(surface: surface, size: 40)
                WidgetTitle(title: surface.title, subtitle: surface.subtitle, titleSize: 15)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
        default:
            // Home Screen small, inside the system's 16pt margins.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    WidgetIris(surface: surface, size: 56)
                    Spacer(minLength: 0)
                    WidgetPlus(size: 32, radius: 10, glyph: 16)
                }
                Spacer(minLength: 0)
                WidgetTitle(title: surface.title, subtitle: surface.subtitle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// The medium blank card: a Take you tap to write into.
struct CardView: View {
    let surface: CaptureSurface
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                WidgetIris(surface: surface, size: 36)
                Text(surface.title)
                    .widgetUI(15, weight: .semibold)
                    .foregroundStyle(mode == .fullColor ? WidgetPalette.text : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                WidgetPlus(size: 26, radius: 8, glyph: 13)
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(mode == .fullColor ? WidgetPalette.lit : Color.white)
                    .frame(width: 2, height: 22)
                    .widgetAccentable()
                Text("Start writing")
                    .widgetUI(17)
                    .foregroundStyle(mode == .fullColor ? WidgetPalette.muted : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetCard()
        .padding(11)
    }
}
