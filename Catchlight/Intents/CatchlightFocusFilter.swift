//
//  CatchlightFocusFilter.swift
//  Catchlight — App Intents (2026-06-23)
//
//  Focus Filter scaffold. Registering a `SetFocusFilterIntent` makes Catchlight
//  appear in Settings → Focus → Add Filter, where the user can pick a scope per
//  Focus mode (Work / Personal / Sleep…). When the Focus activates, iOS calls
//  `perform()`; we persist the chosen scope to the App Group.
//
//  DELIBERATELY INERT FOR NOW (owner 2026-06-23): the live timeline currently
//  ignores the stored scope — wiring it to the actual filter lands with the
//  Sequences/filters work. This file exists so the integration is in place and
//  user-configurable now; the app side is a one-point read (`focus.scope`) when
//  we're ready. No behaviour is invented ahead of that decision.
//

import AppIntents
import CatchlightCore

/// The scope a Focus mode pins Catchlight to. Maps onto the existing/forthcoming
/// timeline filters; today it is stored but not yet applied.
enum FocusScope: String, AppEnum {
    case everything
    case important
    case tasks
    case reminders

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Catchlight Filter")
    static var caseDisplayRepresentations: [FocusScope: DisplayRepresentation] = [
        .everything: "Everything",
        .important: "Important only",
        .tasks: "Tasks",
        .reminders: "Reminders"
    ]
}

struct CatchlightFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Catchlight Filter"
    static var description = IntentDescription(
        "Choose what Catchlight focuses on while this Focus is on."
    )

    // Audit 2026-08, S7: the parameter had no description.
    @Parameter(title: "Show",
               description: "Which Takes Catchlight shows while this Focus is on.",
               default: .everything)
    var scope: FocusScope

    /// Audit 2026-08, S2: one readable sentence in the Focus configuration UI.
    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$scope)")
    }

    /// Shown on the Focus configuration row while active. Reads the enum's own
    /// display representation (audit 2026-08, S7 — this switch duplicated the
    /// localized labels as hard-coded strings, a drift waiting to happen).
    var displayRepresentation: DisplayRepresentation {
        let label = FocusScope.caseDisplayRepresentations[scope]?.title
            ?? LocalizedStringResource(stringLiteral: "Everything")
        return DisplayRepresentation(title: "Catchlight: \(label)")
    }

    func perform() async throws -> some IntentResult {
        // Persist for the app to read once the live filter wiring exists. Inert today.
        UserDefaults(suiteName: CaptureRouting.appGroupSuite)?
            .set(scope.rawValue, forKey: "focus.scope")
        return .result()
    }
}
