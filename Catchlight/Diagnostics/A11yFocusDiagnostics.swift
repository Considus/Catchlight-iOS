//
//  A11yFocusDiagnostics.swift
//  Catchlight
//
//  V40 instrumentation (audit §15ag). Owner on device, VoiceOver running:
//  "Selecting any button it highlights it, may or may not finish saying what it is, then
//  selection jumps up to an Iris without me having a chance to do anything."
//
//  A control the user cannot reach before focus leaves it is not a control, so this is a
//  Blocker. Three candidates were proposed and I eliminated all three by reading: the dock's
//  `.layoutChanged` post fires only when the dock morphs between modes, `RootView`'s
//  `.screenChanged` fires once per unlock, and the Add pulse stops after two cycles. None of
//  them explains "any button, every time".
//
//  🚨 So this does NOT encode a theory. It records two streams and lets them be compared:
//  every accessibility notification the APP posts, and every focus move VoiceOver actually
//  makes. If a post is followed within milliseconds by focus landing somewhere else, the log
//  says which post. If focus moves with no post before it, the cause is an element dying
//  under focus instead, and the log says that too by showing no post at all.
//
//  Silent unless VoiceOver is running, so it costs nothing in normal use. Written to the
//  existing `.lifecycle` channel, which is not user-facing, and reaches the owner through
//  Settings → Export diagnostics with no new plumbing.
//

import Foundation
import UIKit
import CatchlightCore

@MainActor
enum A11yDiag {

    /// Normally silent unless VoiceOver is running, so it costs nothing in ordinary use.
    /// `--a11y-diag` forces it on so the plumbing itself can be PROVEN on the bench: an
    /// instrument that has never produced a line is not an instrument, and this one gets
    /// exactly one chance on a single-use first-run window.
    private static var isRecording: Bool {
        UIAccessibility.isVoiceOverRunning
            || ProcessInfo.processInfo.arguments.contains("--a11y-diag")
    }

    /// Post an accessibility notification AND record it, so a focus move that follows can be
    /// attributed. Call sites use this instead of `UIAccessibility.post` directly.
    static func post(_ notification: UIAccessibility.Notification, argument: Any?, from site: String) {
        if isRecording {
            let name: String
            switch notification {
            case .announcement:  name = "announcement"
            case .layoutChanged: name = "layoutChanged"
            case .screenChanged: name = "screenChanged"
            default:             name = "other(\(notification.rawValue))"
            }
            // 🚨 The ARGUMENT TYPE matters and is the point of recording it. `.layoutChanged`
            // and `.screenChanged` take the element to focus; a String there announces but
            // leaves the focus target unspecified, so VoiceOver re-anchors on its own.
            let argDesc: String
            switch argument {
            case nil:                 argDesc = "nil"
            case let s as String:     argDesc = "String(\"\(s.prefix(40))\")"
            case let o as NSObject:   argDesc = "\(type(of: o))"
            default:                  argDesc = "\(type(of: argument!))"
            }
            DiagnosticsLog.shared.record(.lifecycle, "A11Y POST \(name) arg=\(argDesc) from=\(site)")
        }
        UIAccessibility.post(notification: notification, argument: argument)
    }

    /// Record a line only while instrumentation is recording. For call sites that are not
    /// accessibility posts but whose TIMING needs to sit in the same stream — a collection
    /// reload against a focus move is only meaningful if both are on one clock.
    static func note(_ message: String) {
        guard isRecording else { return }
        DiagnosticsLog.shared.record(.lifecycle, "A11Y \(message)")
    }

    // MARK: - Focus observer

    private static var started = false

    /// Install once at launch. Cheap: the notifications below only fire while an assistive
    /// technology is running.
    static func start() {
        guard !started else { return }
        started = true

        // 🚨 Raise the log's ceilings BEFORE anything is recorded. The first capture came back
        // at 399 lines against a 400 budget: truncated, oldest-first, and the event under
        // investigation happens in the first seconds of the walk. Both the count and the byte
        // ceiling move, because either one alone still evicts oldest-first. Only while
        // recording, so ordinary users keep the small, shareable export.
        if isRecording {
            DiagnosticsLog.maxLifecycleEntries = 20_000
            DiagnosticsLog.maxBytes = 8 * 1024 * 1024
            DiagnosticsLog.shared.record(.lifecycle, "A11Y DIAG budgets raised for capture")
        }

        NotificationCenter.default.addObserver(
            forName: UIAccessibility.elementFocusedNotification, object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                guard isRecording else { return }
                let to = describe(note.userInfo?[UIAccessibility.focusedElementUserInfoKey])
                let from = describe(note.userInfo?[UIAccessibility.unfocusedElementUserInfoKey])
                DiagnosticsLog.shared.record(.lifecycle, "A11Y FOCUS \(from) -> \(to)")
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                DiagnosticsLog.shared.record(
                    .lifecycle,
                    "A11Y VOICEOVER \(UIAccessibility.isVoiceOverRunning ? "ON" : "OFF")")
            }
        }
    }

    /// Label first — it is what identifies the element in the owner's report ("jumps up to an
    /// Iris") — then the type, which says whether it is a real control or a synthesised element.
    private static func describe(_ element: Any?) -> String {
        guard let element else { return "none" }
        let object = element as AnyObject
        let label = (object.accessibilityLabel ?? "") ?? ""
        let type = "\(type(of: object))"
        let trimmed = label.isEmpty ? "(no label)" : String(label.prefix(48))
        return "[\(type)] \"\(trimmed)\""
    }
}
