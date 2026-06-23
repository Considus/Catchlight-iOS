//
//  NewTakeLauncherWidget.swift
//  CatchlightWidgets (2026-06-23)
//
//  The quick-capture launcher — home-screen (small) AND lock-screen accessory
//  (circular + rectangular) from one widget. Tapping opens the app to a blank
//  new Take. No content rendered, so it's safe on the lock screen.
//

import WidgetKit
import SwiftUI

struct NewTakeLauncherWidget: Widget {
    let kind = "NewTakeLauncher"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LauncherProvider()) { _ in
            LauncherView()
                .widgetURL(newTextTakeURL)
                .containerBackground(WidgetPalette.paper, for: .widget)
        }
        .configurationDisplayName("New Take")
        .description("Open Catchlight straight to a new Take.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

private struct LauncherView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            // Lock-screen circular: a ringed + glyph (system-tinted/monochrome).
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("New Take").font(.headline)
                    Text("Catchlight").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
        default:
            // Home-screen small: Ember-ringed + on warm Paper.
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(WidgetPalette.emberOutline.opacity(0.55), lineWidth: 1.5)
                        .frame(width: 56, height: 56)
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(WidgetPalette.emberOutline)
                }
                Text("New Take")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WidgetPalette.ink)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
