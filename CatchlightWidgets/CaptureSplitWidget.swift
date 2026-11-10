//
//  CaptureSplitWidget.swift
//  CatchlightWidgets (2026-06-30)
//
//  The "split in two" launcher — ONE widget with BOTH capture buttons: New Take
//  on the left, New Obie on the right, each with its Iris. An addition
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
                .widgetBackground { WidgetPalette.surface }
        }
        .configurationDisplayName("New Take or Obie")
        .description("Start a Take or an Obie from one widget. Tap the side you need.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
        .contentMarginsDisabled()   // SplitView sets its own 11pt inset
    }
}

/// Two tappable halves (Take | Obie), parameterised per family.
struct SplitView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            // Lock Screen: two halves with a hairline between.
            HStack(spacing: 0) {
                captureButton(.take) { accessoryHalf(.take) }
                Rectangle().fill(Color.primary.opacity(0.28)).frame(width: 1).padding(.vertical, 12)
                captureButton(.obie) { accessoryHalf(.obie) }
            }
        default:
            // Home Screen medium: two cards 8pt apart, 11pt in from the edge.
            HStack(spacing: 8) {
                captureButton(.take) { mediumHalf(.take).widgetCard() }
                captureButton(.obie) { mediumHalf(.obie).widgetCard() }
            }
            .padding(11)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                WidgetIris(surface: surface, size: 44)
                Spacer(minLength: 0)
                WidgetPlus(size: 22, radius: 7, glyph: 11)
            }
            Spacer(minLength: 0)
            WidgetTitle(title: surface.shortTitle, subtitle: surface.subtitle)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())   // the whole half is tappable, not just the Iris
    }

    /// One half of the wide Lock Screen widget: the Iris and "Take" or "Obie" beside it, on
    /// one line at full size. Each half is only about 80pt wide, so the second line is gone
    /// and the title is the noun alone, the same word in every language ("Neuer Take" broke
    /// mid-word in German). VoiceOver still says the full "New Take" or "New Obie" (Art
    /// Director, 2026-11-10).
    private func accessoryHalf(_ surface: CaptureSurface) -> some View {
        HStack(spacing: 4) {
            WidgetIris(surface: surface, size: 22)
            Text(surface.shortTitle)
                .widgetUI(14, weight: .semibold)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(surface.title)
    }
}
