//
//  WidgetSupport.swift
//  CatchlightWidgets — shared theme, provider, views (2026-06-23)
//
//  All Catchlight widgets are LAUNCHERS: a single static entry, no timeline
//  refresh, no Take content. They render brand chrome and a deep link; tapping
//  opens the app to capture. Because nothing is decrypted or displayed, the
//  keychain wall is irrelevant here (owner 2026-06-22, Ideas Backlog §7).
//
//  Take and Obie widgets share these views, parameterised by `CaptureSurface`
//  (owner 2026-06-23: every Take widget has an Obie twin). Brand colours are
//  inlined (the app's asset catalog isn't linked into the extension); visual
//  polish is a device-review pass.
//

import WidgetKit
import SwiftUI
import CatchlightCore

// MARK: - Brand palette (subset, inlined for the extension)

enum WidgetPalette {
    static let paper = Color(red: 0.969, green: 0.953, blue: 0.925)   // #F7F3EC
    static let ink = Color(red: 0.102, green: 0.090, blue: 0.078)     // #1A1714
    static let ember = Color(red: 0.788, green: 0.663, blue: 0.431)   // #C9A96E
    static let emberOutline = Color(red: 0.522, green: 0.396, blue: 0.224) // #856539
}

// MARK: - Capture surface (Take vs Obie presentation)

/// Describes what one launcher/card renders and where it routes. The Obie
/// variant uses a filled gold treatment + crown glyph to read as "the one";
/// Take uses the Ember outline.
struct CaptureSurface {
    let url: URL
    let title: String        // "New Take" / "New Obie"
    let cardPrompt: String    // medium-card placeholder
    let glyph: String         // SF Symbol for the launcher mark
    let isObie: Bool

    static let take = CaptureSurface(
        url: CaptureRouting.captureURL(.text),
        title: "New Take",
        cardPrompt: "Tap to write a Take…",
        glyph: "plus",
        isObie: false
    )

    static let obie = CaptureSurface(
        url: CaptureRouting.captureURL(.obie),
        title: "New Obie",
        cardPrompt: "Tap to set your Obie…",
        glyph: "crown.fill",
        isObie: true
    )
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

// MARK: - Shared views

/// Home-small + lock-screen accessory launcher, parameterised by surface.
struct LauncherView: View {
    let surface: CaptureSurface
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: surface.isObie ? "crown.fill" : "plus.circle.fill")
                    .font(.system(size: surface.isObie ? 20 : 24, weight: .semibold))
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: surface.isObie ? "crown.fill" : "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(surface.title).font(.headline)
                    Text("Catchlight").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
        default:
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(surface.isObie ? WidgetPalette.ember.opacity(0.9) : .clear)
                        .frame(width: 56, height: 56)
                    Circle()
                        .stroke(WidgetPalette.emberOutline.opacity(0.55),
                                lineWidth: surface.isObie ? 0 : 1.5)
                        .frame(width: 56, height: 56)
                    Image(systemName: surface.glyph)
                        .font(.system(size: surface.isObie ? 22 : 26,
                                      weight: surface.isObie ? .semibold : .light))
                        .foregroundStyle(surface.isObie ? WidgetPalette.ink : WidgetPalette.emberOutline)
                }
                Text(surface.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WidgetPalette.ink)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Medium "blank Take/Obie card" — styled as a Take row you tap to write into.
struct CardView: View {
    let surface: CaptureSurface

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(surface.isObie ? WidgetPalette.ember.opacity(0.9) : .clear)
                    .frame(width: 40, height: 40)
                Circle()
                    .stroke(WidgetPalette.emberOutline.opacity(0.5),
                            lineWidth: surface.isObie ? 0 : 1.5)
                    .frame(width: 40, height: 40)
                Image(systemName: surface.glyph)
                    .font(.system(size: surface.isObie ? 16 : 18,
                                  weight: surface.isObie ? .semibold : .light))
                    .foregroundStyle(surface.isObie ? WidgetPalette.ink : WidgetPalette.emberOutline)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(surface.cardPrompt)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(WidgetPalette.ink.opacity(0.55))
                Text(surface.title)
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
