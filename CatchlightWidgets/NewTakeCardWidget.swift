//
//  NewTakeCardWidget.swift
//  CatchlightWidgets (2026-06-23)
//
//  The medium "blank Take card" (owner 2026-06-23). Styled as a real Take row
//  with an empty Iris and a "Tap to write a Take…" placeholder, so it reads as
//  a Take you write into. WidgetKit can't host a keyboard, so tapping opens the
//  app's inline editor — typing happens there. Owner is trialling its value on
//  device; nothing here renders existing Takes (privacy-clean blank surface).
//

import WidgetKit
import SwiftUI

struct NewTakeCardWidget: Widget {
    let kind = "NewTakeCard"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LauncherProvider()) { _ in
            CardView()
                .widgetURL(newTextTakeURL)
                .containerBackground(WidgetPalette.paper, for: .widget)
        }
        .configurationDisplayName("New Take card")
        .description("A blank Take to tap and write into.")
        .supportedFamilies([.systemMedium])
    }
}

private struct CardView: View {
    var body: some View {
        HStack(spacing: 14) {
            // Empty Iris — a hollow ring with a faint diamond aperture, echoing
            // the timeline's Take circle without committing to a quadrant.
            ZStack {
                Circle()
                    .stroke(WidgetPalette.emberOutline.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 40, height: 40)
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(WidgetPalette.emberOutline)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Tap to write a Take…")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(WidgetPalette.ink.opacity(0.55))
                Text("New Take")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetPalette.emberOutline)
                    .textCase(.uppercase)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WidgetPalette.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(WidgetPalette.emberOutline.opacity(0.18), lineWidth: 0.75)
                )
        )
    }
}
