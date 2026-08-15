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

//  LAUNCHER ONLY as of 2026-08-11: the text parameter moved to `CaptureTakeIntent` /
//  `CaptureObieIntent`. It was Optional here, and App Intents never requests a value for an
//  optional parameter, so Siri opened a blank editor instead of asking what to capture
//  (device-confirmed). One parameter cannot be both required for Siri and absent for the
//  Control, so the intent became two. This one opens a blank editor and takes no input.
//

import AppIntents
import CatchlightCore

struct NewTakeIntent: AppIntent {
    static var title: LocalizedStringResource = "New Take"
    static var description = IntentDescription(
        "Open Catchlight and start a new Take.",
        categoryName: "Capture"
    )

    /// Bring Catchlight to the foreground — capture runs in-app (see file note).
    /// iOS 18 reads this. iOS 26 reads `supportedModes` below instead.
    static var openAppWhenRun: Bool = true

    /// iOS 26 reads this. FRONT ONLY, and deliberately so (2026-08-15): this intent opens an
    /// empty editor and carries no text, so a background run has nothing to do and breaks it.
    /// The behaviour must stay the same as it is on iOS 18. This declaration is API currency.
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Record the request for the app to drain once it's foregrounded AND
        // unlocked (CatchlightApp.drainPendingCapture). Cross-process safe — this
        // may run in the Shortcuts/Control extension, not the app.
        CaptureRouting.setPending(.init(mode: .text))
        return .result()
    }
}
