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

    private static var budgetsRaised = false

    /// Idempotent, and called from BOTH launch and the VoiceOver status change.
    private static func raiseBudgetsIfRecording() {
        guard isRecording, !budgetsRaised else { return }
        budgetsRaised = true
        DiagnosticsLog.maxLifecycleEntries = 20_000
        DiagnosticsLog.maxBytes = 8 * 1024 * 1024
        DiagnosticsLog.shared.record(.lifecycle, "A11Y DIAG budgets raised for capture")
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
        raiseBudgetsIfRecording()

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
                // 🚨 Raise the budgets HERE as well, not only at launch. Measured on the
                // owner's second capture: it came back at 399 lines against the 400 ceiling
                // AGAIN, with no "budgets raised" line at all — because he turns VoiceOver on
                // AFTER opening the app, so `isRecording` was false when `start()` ran and the
                // raise never happened. A fix that only takes effect on a path the user does
                // not use is not a fix.
                raiseBudgetsIfRecording()
                DiagnosticsLog.shared.record(
                    .lifecycle,
                    "A11Y VOICEOVER \(UIAccessibility.isVoiceOverRunning ? "ON" : "OFF")")
            }
        }
    }

    // MARK: - Sorted-order dump (V40)

    /// Walk the key window's accessibility tree IN THE ORDER VOICEOVER WALKS IT and log it.
    ///
    /// 🚨 Why this exists when two probes already dump trees: XCUITest reads the VIEW
    /// HIERARCHY from outside the process, which is NOT VoiceOver's traversal order — the
    /// hierarchy dumps show the dock ahead of the timeline despite V30 sorting it last, so
    /// they demonstrate their own blind spot. `accessibilityElements` /
    /// `accessibilityElementCount()` are the UIAccessibility container protocol, which IS
    /// what an assistive technology enumerates, so sort priority is already applied here.
    ///
    /// This is the only instrument that can see the remaining half of V40 — whether every
    /// dock element is the end of its own run — WITHOUT the owner's device.
    ///
    /// Runs only under `--a11y-order-dump`, and reads the tree rather than changing it.
    /// Prints to stdout rather than NSLog: the unified log REDACTS dynamic values, so every
    /// label came back as "" through `log stream` (measured 2026-09-08).
    @MainActor
    static func dumpSortedOrderIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--a11y-order-dump") else { return }
        // Dump REPEATEDLY, not once. V45 needs the tree read AFTER an interaction — the
        // question is whether a flag stays set once an overlay closes — and a single
        // dump three seconds after launch can only ever describe the resting state.
        for tick in 0..<7 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0 + Double(tick) * 5.0) {
            MainActor.assumeIsolated {
                guard let window = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene }).first?
                        .windows.first(where: \.isKeyWindow) else {
                    emit("A11Y ORDER: no key window")
                    return
                }
                // Type-level, as `raiseBudgetsIfRecording` does — these are static.
                DiagnosticsLog.maxLifecycleEntries = max(DiagnosticsLog.maxLifecycleEntries, 2_000)
                DiagnosticsLog.maxBytes = max(DiagnosticsLog.maxBytes, 4 * 1024 * 1024)
                emit("A11Y ORDER BEGIN tick=\(tick)")
                var index = 0
                walk(window, depth: 0, index: &index)
                emit("A11Y ORDER END tick=\(tick) (\(index) elements)")
            }
            }
        }
    }

    /// What KIND of container this is. A `.semanticGroup` or `.list` is a boundary
    /// VoiceOver can cycle inside, which is the shape the owner's fourth capture has:
    /// the traversal returns to the collection's first cell ten times and never once
    /// reaches the heading or the pinned Obie above it.
    private static func containerType(_ object: NSObject) -> String {
        switch object.accessibilityContainerType {
        case .none: return "none"
        case .dataTable: return "dataTable"
        case .list: return "LIST"
        case .landmark: return "landmark"
        case .semanticGroup: return "SEMANTIC_GROUP"
        @unknown default: return "unknown"
        }
    }

    /// The chain of containers an element reports itself as belonging to. If the
    /// timeline cells, the hint and the dock name a common ancestor that the heading
    /// and the Obie do not, that ancestor is the boundary being cycled within.
    private static func containerChain(_ object: NSObject) -> String {
        // `accessibilityContainer` lives on UIAccessibilityElement, not NSObject; a
        // UIView reports its place through the view tree instead. Ask whichever applies.
        var names: [String] = []
        // SwiftUI's `AccessibilityNode` is neither a UIView nor a UIAccessibilityElement,
        // so the typed routes both return nil for it and the chain reads "(none)" for the
        // whole tree — an instrument failure that could be mistaken for "no container".
        // `accessibilityContainer` is an ObjC property, so ask the runtime directly.
        func parent(_ o: NSObject) -> NSObject? {
            if let el = o as? UIAccessibilityElement { return el.accessibilityContainer as? NSObject }
            let sel = NSSelectorFromString("accessibilityContainer")
            if o.responds(to: sel), let got = o.perform(sel)?.takeUnretainedValue() as? NSObject { return got }
            if let v = o as? UIView { return v.superview }
            return nil
        }
        var current: NSObject? = parent(object)
        var hops = 0
        while let c = current, hops < 6 {
            names.append("\(type(of: c))")
            current = parent(c)
            hops += 1
        }
        return names.isEmpty ? "(none)" : names.joined(separator: "<-")
    }

    /// stdout AND the persisted log. `simctl launch --console` proved unreliable to
    /// capture (three attempts returned only the PID line), so the log file — readable
    /// from the app container with `simctl get_app_container` — is the dependable
    /// channel. The budget raise below keeps a ~100-line dump from evicting itself.
    private static func emit(_ line: String) {
        print(line)
        DiagnosticsLog.shared.record(.lifecycle, line)
    }

    /// Depth-first in container order — the same walk VoiceOver's next/previous performs.
    @MainActor
    private static func walk(_ node: Any, depth: Int, index: inout Int) {
        guard depth < 40, index < 400 else { return }
        let pad = String(repeating: "  ", count: depth)

        // A container vends children through EITHER the array or the indexed pair; UIKit
        // classes commonly implement only the latter, so both are asked.
        if let object = node as? NSObject {
            if let children = object.accessibilityElements, !children.isEmpty {
                emit("A11Y ORDER \(pad)[container \(type(of: object)) n=\(children.count) ctype=\(containerType(object))]")
                for child in children { walk(child, depth: depth + 1, index: &index) }
                return
            }
            let count = object.accessibilityElementCount()
            if count != NSNotFound && count > 0 {
                emit("A11Y ORDER \(pad)[container \(type(of: object)) n=\(count) ctype=\(containerType(object))]")
                for i in 0..<count {
                    if let child = object.accessibilityElement(at: i) { walk(child, depth: depth + 1, index: &index) }
                }
                return
            }
            if object.isAccessibilityElement {
                index += 1
                emit("A11Y ORDER \(pad)\(index) \(object.accessibilityLabel ?? "(no label)") | \(type(of: object)) | in=\(containerChain(object))")
                return
            }
            if let view = object as? UIView {
                for sub in view.subviews { walk(sub, depth: depth + 1, index: &index) }
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
