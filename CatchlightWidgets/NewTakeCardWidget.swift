//
//  NewTakeCardWidget.swift
//  CatchlightWidgets (2026-06-23)
//
//  The medium "blank card" (owner 2026-06-23). Styled as a Take card you tap
//  to write into. WidgetKit can't host a keyboard, so tapping opens the app's
//  inline editor — typing happens there. Take + Obie twins, shared CardView.
//

import WidgetKit
import SwiftUI

struct NewTakeCardWidget: Widget {
    let kind = "NewTakeCard"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LauncherProvider()) { _ in
            CardView(surface: .take)
                .widgetURL(CaptureSurface.take.url)
                .widgetBackground { WidgetPalette.surface }
        }
        .configurationDisplayName("New Take card")
        .description("Write straight into a blank Take.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()   // CardView sets its own 11pt inset
    }
}

struct NewObieCardWidget: Widget {
    let kind = "NewObieCard"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LauncherProvider()) { _ in
            CardView(surface: .obie)
                .widgetURL(CaptureSurface.obie.url)
                .widgetBackground { WidgetPalette.surface }
        }
        .configurationDisplayName("New Obie card")
        .description("Write straight into a blank Obie.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()   // CardView sets its own 11pt inset
    }
}
