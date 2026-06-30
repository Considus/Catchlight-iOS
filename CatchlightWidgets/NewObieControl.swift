//
//  NewObieControl.swift
//  CatchlightWidgets (2026-06-23)
//
//  iOS-18 Control twin of NewTakeControl — Control Center / Lock Screen /
//  Action button. Driven by NewObieIntent, so it opens the app to a new Take
//  pre-flagged as the Obie (the store demotes the previous Obie on save).
//

import WidgetKit
import SwiftUI
import AppIntents

struct NewObieControl: ControlWidget {
    let kind = "com.considus.catchlight.NewObieControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: kind) {
            ControlWidgetButton(action: NewObieIntent()) {
                Label("New Obie", systemImage: "crown.fill")
            }
            // Brand gold instead of the system default tint (blue). Obie keeps
            // crown.fill — Controls are SF-Symbol-only, so the in-app petal glyph
            // can't render here (owner 2026-06-30 widget pass). Ember = #C9A96E.
            .tint(Color(.sRGB, red: 0.788, green: 0.663, blue: 0.431, opacity: 1.0))
        }
        .displayName("New Obie")
        .description("Open Catchlight and capture your Obie.")
    }
}
