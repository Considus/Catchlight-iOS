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
                // The Iris symbol drawn for controls: a template SF Symbol, which a
                // Control accepts and tints (`Assets.xcassets/NewTakeSymbol.symbolset`).
                Label("New Take", image: "NewTakeSymbol")
            }
            // The Scene accent, Night or Daylight (spec R18).
            .tint(WidgetPalette.accent)
        }
        .displayName("New Take")
        .description("Open Catchlight to a new Take.")
    }
}
