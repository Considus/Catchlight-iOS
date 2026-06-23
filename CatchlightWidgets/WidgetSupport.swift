//
//  WidgetSupport.swift
//  CatchlightWidgets — shared theme + provider (2026-06-23)
//
//  All Catchlight widgets are LAUNCHERS: a single static entry, no timeline
//  refresh, no Take content. They render brand chrome and a deep link; tapping
//  opens the app to capture. Because nothing is decrypted or displayed, the
//  keychain wall is irrelevant here (owner 2026-06-22, Ideas Backlog §7).
//
//  Brand colours are inlined (the app's asset catalog isn't linked into the
//  extension). First-cut palette from the HiFi / Design System: warm Paper
//  surface + Ember accent. Visual polish is a device-review pass — widgets are
//  inherently a see-it-to-tune-it surface.
//

import WidgetKit
import SwiftUI
import CatchlightCore

// MARK: - Brand palette (subset, inlined for the extension)

enum WidgetPalette {
    /// Warm Paper surface (Daylight). System materials handle the lock-screen
    /// accessory tint, so these apply to the home-screen families.
    static let paper = Color(red: 0.969, green: 0.953, blue: 0.925)   // #F7F3EC
    static let ink = Color(red: 0.102, green: 0.090, blue: 0.078)     // #1A1714
    /// Ember accent (fill) and its deeper outline-on-paper variant.
    static let ember = Color(red: 0.788, green: 0.663, blue: 0.431)   // #C9A96E
    static let emberOutline = Color(red: 0.522, green: 0.396, blue: 0.224) // #856539
}

// MARK: - Static launcher timeline

struct LauncherEntry: TimelineEntry {
    let date: Date
}

/// One fixed entry; launchers never need to refresh (`.never`).
struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry { LauncherEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
        completion(LauncherEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        completion(Timeline(entries: [LauncherEntry(date: Date())], policy: .never))
    }
}

/// The deep link every launcher opens. Text capture for now; the audio widget
/// will hand `.audio` to the same route once recording ships.
let newTextTakeURL = CaptureRouting.captureURL(.text)
