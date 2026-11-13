//
//  TouchTargetAudit.swift
//  CatchlightUITests
//
//  Walks the accessibility tree of the screen on show and measures every control that takes a
//  touch. Apple's Human Interface Guidelines (Accessibility, Mobility) give 44x44 pt as the
//  default control size on iOS and iPadOS, and 28x28 pt as the minimum. This holds the app to
//  the default.
//
//  What it measures is the accessibility frame, which SwiftUI sets from the control's layout
//  frame. A `.contentShape` that reaches past that frame does not widen it, so a control that
//  passes here has a hit area of at least that frame, and the fix for one that fails is a larger
//  frame (padding or `.frame(minWidth:minHeight:)`), not a `contentShape` alone.
//

import XCTest

/// The least width and height, in points, a control may have.
let touchTargetMinimum: CGFloat = 44

struct MeasuredControl: CustomStringConvertible {
    let type: String
    let identifier: String
    let label: String
    let frame: CGRect

    var name: String { identifier.isEmpty ? "\"\(label)\"" : identifier }
    var description: String {
        "\(type) \(name) \(String(format: "%.1f", frame.width))x\(String(format: "%.1f", frame.height))"
    }
}

/// The element types that take a touch. System chrome (keyboard, status bar, scroll bars) is left out.
private let touchTypes: Set<XCUIElement.ElementType> = [
    .button, .switch, .toggle, .link, .segmentedControl, .slider, .stepper, .menuItem, .tab, .radioButton,
    .checkBox, .popUpButton, .menuButton, .disclosureTriangle,
]
private let chromeTypes: Set<XCUIElement.ElementType> = [.keyboard, .statusBar, .scrollBar, .key]

/// Identifiers of controls SwiftUI exposes as `.other` rather than `.button` on some runtimes.
let touchTargetOtherIDs: Set<String> = [
    "editor-shape", "take-iris", "angle-reorder", "angle-checkbox",
]

/// Every touch control on screen right now, with its measured frame.
func measureControls(in app: XCUIApplication) -> [MeasuredControl] {
    guard let root = try? app.snapshot() else { return [] }
    let screen = app.frame
    var found: [MeasuredControl] = []
    func visit(_ s: XCUIElementSnapshot) {
        if chromeTypes.contains(s.elementType) { return }
        let f = s.frame
        let isTouch = touchTypes.contains(s.elementType) || touchTargetOtherIDs.contains(s.identifier)
        if isTouch, f.width > 0, f.height > 0, f.intersects(screen) {
            found.append(MeasuredControl(type: "\(s.elementType.rawValue)", identifier: s.identifier,
                                         label: s.label, frame: f))
        }
        for child in s.children { visit(child) }
    }
    visit(root)
    return found
}

/// iOS draws these, not the app. They are measured and logged, never failed (owner, 12 Nov 2026:
/// "Apple's controls stay as Apple intended").
let systemControlLabels: Set<String> = ["Sheet Grabber", "Continue"]

/// Records every control on the screen to the audit log (`TOUCH_AUDIT_LOG` when set, else the
/// test output) and fails once for each under 44x44. `exceptions` names controls (by identifier or
/// label) that are known short, each with its reason at the call site.
@discardableResult
func auditTouchTargets(_ screen: String, in app: XCUIApplication, allowing exceptions: Set<String> = [],
                       file: StaticString = #filePath, line: UInt = #line) -> [MeasuredControl] {
    let controls = measureControls(in: app)
    XCTAssertFalse(controls.isEmpty, "\(screen): no controls found, so nothing was measured", file: file, line: line)
    var short: [MeasuredControl] = []
    for c in controls {
        let ok = c.frame.width >= touchTargetMinimum - 0.5 && c.frame.height >= touchTargetMinimum - 0.5
        let line = "TA|\(screen)|\(c.type)|\(c.identifier)|\(c.label)|\(c.frame.width)|\(c.frame.height)|\(ok ? "ok" : "SHORT")"
        print(line)
        if let path = ProcessInfo.processInfo.environment["TOUCH_AUDIT_LOG"] {
            if let h = FileHandle(forWritingAtPath: path) {
                h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); h.closeFile()
            } else {
                try? (line + "\n").write(toFile: path, atomically: false, encoding: .utf8)
            }
        }
        if !ok, !exceptions.contains(c.identifier), !exceptions.contains(c.label), !systemControlLabels.contains(c.label) { short.append(c) }
    }
    for c in short {
        XCTFail("\(screen): \(c) is under 44x44", file: file, line: line)
    }
    return short
}
