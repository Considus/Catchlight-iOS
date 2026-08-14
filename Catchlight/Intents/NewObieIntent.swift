//
//  NewObieIntent.swift
//  Catchlight — App Intents (2026-06-23)
//
//  "Obie this in Catchlight" — capture a new Take and make it your Obie in one
//  step. Mirrors NewTakeIntent exactly, but carries the `.obie` capture mode:
//  the app creates the Take pre-flagged as the Obie, and the store's single-Obie
//  upsert demotes the previous Obie on save (owner 2026-06-23 — set it in process,
//  remove the old, no confirmation).
//
//  Shared into the widget extension (see project.yml's CatchlightWidgets sources)
//  — the Obie Control, launcher widget, and split widget all fire it via
//  `Button(intent:)`.
//

//  LAUNCHER ONLY as of 2026-08-11: the text parameter moved to `CaptureTakeIntent` /
//  `CaptureObieIntent`. It was Optional here, and App Intents never requests a value for an
//  optional parameter, so Siri opened a blank editor instead of asking what to capture
//  (device-confirmed). One parameter cannot be both required for Siri and absent for the
//  Control, so the intent became two. This one opens a blank editor and takes no input.
//

import AppIntents
import CatchlightCore

struct NewObieIntent: AppIntent {
    static var title: LocalizedStringResource = "New Obie"
    static var description = IntentDescription(
        "Open Catchlight and open a blank Obie.",
        categoryName: "Capture"
    )

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureRouting.setPending(.init(mode: .obie))
        return .result()
    }
}
