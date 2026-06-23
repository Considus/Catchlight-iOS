//
//  NewTakeCardWidget.swift
//  CatchlightWidgets (2026-06-23)
//
//  The medium "blank card" (owner 2026-06-23). Styled as a real Take row you tap
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
                .containerBackground(WidgetPalette.paper, for: .widget)
        }
        .configurationDisplayName("New Take card")
        .description("A blank Take to tap and write into.")
        .supportedFamilies([.systemMedium])
    }
}

struct NewObieCardWidget: Widget {
    let kind = "NewObieCard"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LauncherProvider()) { _ in
            CardView(surface: .obie)
                .widgetURL(CaptureSurface.obie.url)
                .containerBackground(WidgetPalette.paper, for: .widget)
        }
        .configurationDisplayName("New Obie card")
        .description("A blank Obie to tap and write into.")
        .supportedFamilies([.systemMedium])
    }
}
