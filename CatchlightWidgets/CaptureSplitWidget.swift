//
//  CaptureSplitWidget.swift
//  CatchlightWidgets (2026-06-30)
//
//  The "split in two" launcher — ONE widget with BOTH capture buttons: New Take
//  (the Catchlight "C") on the left, New Obie (the "O") on the right. An addition
//  to the single-purpose launchers, not a replacement (owner 2026-06-30).
//
//  Two independent tap targets in one widget need `Button(intent:)` — `widgetURL`
//  only gives a single whole-widget tap. Each half runs the SAME capture intent as
//  the Controls/Shortcuts (`openAppWhenRun` → opens the app to the right capture).
//
//  Families: systemMedium (home) + accessoryRectangular (lock screen). A Control
//  can't be split — a ControlWidgetButton is a single action by design — so there
//  is no split Control; the separate New Take / New Obie controls remain.
//

import WidgetKit
import SwiftUI
import AppIntents

struct CaptureSplitWidget: Widget {
    let kind = "CaptureSplit"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LauncherProvider()) { _ in
            SplitView()
                .containerBackground(WidgetPalette.background, for: .widget)
        }
        .configurationDisplayName("New Take or Obie")
        .description("Both capture buttons in one widget — tap the side you need.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

/// Two tappable halves (Take | Obie), parameterised per family.
struct SplitView: View {
    @Environment(\.widgetFamily) private var family
    /// The system's widget content margin — reused as the gap between the two cards
    /// so the border BETWEEN them equals the border AROUND them (owner 2026-06-30).
    @Environment(\.widgetContentMargins) private var margins

    var body: some View {
        switch family {
        case .accessoryRectangular:
            // Lock screen — system vibrant/monochrome; two glyph buttons side by side.
            HStack(spacing: 0) {
                captureButton(.take) { accessoryHalf(.take) }
                Rectangle().fill(.secondary).frame(width: 0.5).opacity(0.4)
                captureButton(.obie) { accessoryHalf(.obie) }
            }
        default:
            // Home medium — TWO individual cards with an even gap == the surround.
            HStack(spacing: margins.leading) {
                captureButton(.take) { mediumHalf(.take).widgetCardSurface(isObie: false) }
                captureButton(.obie) { mediumHalf(.obie).widgetCardSurface(isObie: true) }
            }
        }
    }

    /// Wraps a half in the matching capture intent (Take → NewTakeIntent, etc.).
    @ViewBuilder
    private func captureButton<Content: View>(_ surface: CaptureSurface,
                                              @ViewBuilder _ content: () -> Content) -> some View {
        if surface.isObie {
            Button(intent: NewObieIntent()) { content() }.buttonStyle(.plain)
        } else {
            Button(intent: NewTakeIntent()) { content() }.buttonStyle(.plain)
        }
    }

    private func mediumHalf(_ surface: CaptureSurface) -> some View {
        VStack(spacing: 10) {
            WidgetGlyphMark(asset: surface.glyphAsset, height: 44, tint: surface.glyphTint,
                            opticalScale: surface.glyphOpticalScale,
                            inkOffsetFraction: surface.glyphInkOffsetFraction)
            Text(surface.title)
                .font(WidgetFont.ui(14, weight: .medium))
                .foregroundStyle(WidgetPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())   // the whole half is tappable, not just the glyph
    }

    private func accessoryHalf(_ surface: CaptureSurface) -> some View {
        VStack(spacing: 2) {
            WidgetGlyphMark(asset: surface.glyphAsset, height: 22,
                            opticalScale: surface.glyphOpticalScale,
                            inkOffsetFraction: surface.glyphInkOffsetFraction)
            Text(surface.isObie ? "Obie" : "Take").font(.caption2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}
