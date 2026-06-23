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
        }
        .displayName("New Obie")
        .description("Open Catchlight and capture your Obie.")
    }
}
