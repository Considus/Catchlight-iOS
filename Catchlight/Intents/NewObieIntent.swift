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

import AppIntents
import CatchlightCore

struct NewObieIntent: AppIntent {
    static var title: LocalizedStringResource = "New Obie"
    static var description = IntentDescription(
        "Open Catchlight and capture a new Take as your Obie. Optionally pass the text.",
        categoryName: "Capture"
    )

    static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Obie",
        description: "Text to capture as your new Obie. Leave empty to open a blank Obie.",
        requestValueDialog: "What's the Obie?"
    )
    var text: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureRouting.setPending(.init(mode: .obie, text: text))
        return .result()
    }
}
