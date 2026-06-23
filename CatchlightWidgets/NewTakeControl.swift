//
//  NewTakeControl.swift
//  CatchlightWidgets (2026-06-23)
//
//  iOS-18 Control — Control Center, the Lock Screen, and assignable directly to
//  the Action button. Powered by the SAME NewTakeIntent as Shortcuts/Siri, so
//  one intent drives every capture surface. Opens the app to a blank Take
//  (`openAppWhenRun`), so it's a native, snappier route than wrapping a Shortcut.
//

import WidgetKit
import SwiftUI
import AppIntents

struct NewTakeControl: ControlWidget {
    let kind = "com.considus.catchlight.NewTakeControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: kind) {
            ControlWidgetButton(action: NewTakeIntent()) {
                Label("New Take", systemImage: "plus.circle.fill")
            }
        }
        .displayName("New Take")
        .description("Open Catchlight to a new Take.")
    }
}
