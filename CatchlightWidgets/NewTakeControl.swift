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
                // The Catchlight "C" brand mark as a custom SF Symbol (Controls render
                // SF Symbols, not image assets). Pairs with the Obie "O" Control
                // (owner 2026-06-30). `Assets.xcassets/CatchlightSymbol.symbolset`.
                Label("New Take", image: "CatchlightSymbol")
            }
            // Brand gold instead of the system default tint (green). iOS Controls
            // only tint within their fixed style, but this carries the Catchlight
            // accent through (owner 2026-06-30 widget pass). Ember = #C9A96E.
            .tint(Color(.sRGB, red: 0.788, green: 0.663, blue: 0.431, opacity: 1.0))
        }
        .displayName("New Take")
        .description("Open Catchlight to a new Take.")
    }
}
