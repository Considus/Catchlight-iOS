//
//  NewTakeIntent.swift
//  Catchlight — App Intents (2026-06-23)
//
//  The single capture intent that powers FOUR surfaces at once: the Shortcuts
//  action, the Siri phrase (via `CatchlightAppShortcuts`), the Action button,
//  and the iOS-18 Control. The home/lock/medium WIDGETS deep-link via
//  `widgetURL` instead (a launcher doesn't need an in-process intent), but they
//  funnel into the SAME `CaptureRouting` hand-off the app drains.
//
//  `openAppWhenRun = true`: capture always happens IN the app. That's deliberate
//  — the encrypted store needs the master key, which only materialises in the
//  foreground/unlocked app (the zero-knowledge wall blocks silent background
//  writes). So the intent records a pending capture and lets the app open and
//  route; it never touches the store itself.
//
//  TEXT param: optional. Empty/absent → open a blank editor (the launcher case,
//  shared with widgets/Control/Action button). Supplied → Siri/Shortcuts
//  "Add a Take 'buy milk'" pre-fills the new Take with the user's own words.
//

import AppIntents
import CatchlightCore

struct NewTakeIntent: AppIntent {
    static var title: LocalizedStringResource = "New Take"
    static var description = IntentDescription(
        "Open Catchlight and start a new Take. Optionally pass text to capture it straight away.",
        categoryName: "Capture"
    )

    /// Bring Catchlight to the foreground — capture runs in-app (see file note).
    static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Take",
        description: "Text to capture as a new Take. Leave empty to open a blank Take.",
        requestValueDialog: "What's the Take?"
    )
    var text: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        // Record the request for the app to drain once it's foregrounded AND
        // unlocked (CatchlightApp.drainPendingCapture). Cross-process safe — this
        // may run in the Shortcuts/Control extension, not the app.
        CaptureRouting.setPending(.init(mode: .text, text: text))
        return .result()
    }
}
