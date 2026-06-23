//
//  NewTakeLauncherWidget.swift
//  CatchlightWidgets (2026-06-23)
//
//  Quick-capture launchers — home-screen (small) AND lock-screen accessory
//  (circular + rectangular). Tapping opens the app to a blank new Take / Obie.
//  No content rendered, so safe on the lock screen. Shared LauncherView, two
//  surfaces.
//

import WidgetKit
import SwiftUI

struct NewTakeLauncherWidget: Widget {
    let kind = "NewTakeLauncher"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LauncherProvider()) { _ in
            LauncherView(surface: .take)
                .widgetURL(CaptureSurface.take.url)
                .containerBackground(WidgetPalette.paper, for: .widget)
        }
        .configurationDisplayName("New Take")
        .description("Open Catchlight straight to a new Take.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct NewObieLauncherWidget: Widget {
    let kind = "NewObieLauncher"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LauncherProvider()) { _ in
            LauncherView(surface: .obie)
                .widgetURL(CaptureSurface.obie.url)
                .containerBackground(WidgetPalette.paper, for: .widget)
        }
        .configurationDisplayName("New Obie")
        .description("Open Catchlight and capture your Obie.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}
