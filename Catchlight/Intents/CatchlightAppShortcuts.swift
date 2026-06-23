//
//  CatchlightAppShortcuts.swift
//  Catchlight — App Intents (2026-06-23)
//
//  The ready-made Shortcuts "Library" (owner's term). An `AppShortcutsProvider`
//  ships curated, zero-assembly shortcuts that appear automatically in the
//  Shortcuts app under Catchlight the moment the app is installed, each with a
//  Siri trigger phrase and Spotlight surfacing — no user setup.
//
//  Every phrase MUST contain `\(.applicationName)` (an App Intents requirement).
//  Up to 10 App Shortcuts are allowed per app; we ship one now (New Take) and
//  the richer read/write actions (Search, Mark Done, Obie) join later with the
//  Take `AppEntity`.
//

import AppIntents

struct CatchlightAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Phrases lead with / prominently feature the app name and avoid "Add a…",
        // which Siri routes to its built-in Reminders intent (owner-reported
        // 2026-06-23: "Add a Take, buy milk" created an Apple Reminder). A free-text
        // body can't be embedded in the phrase itself — say the trigger, then Siri
        // prompts ("What's the Take?" / "What's the Obie?") and you dictate it.
        // Two parallel sets (owner 2026-06-23): every Take phrase has an Obie twin.
        AppShortcut(
            intent: NewTakeIntent(),
            phrases: [
                "New Take in \(.applicationName)",
                "Take this in \(.applicationName)",
                "New \(.applicationName) Take",
                "Start a Take in \(.applicationName)"
            ],
            shortTitle: "New Take",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: NewObieIntent(),
            phrases: [
                "New Obie in \(.applicationName)",
                "Obie this in \(.applicationName)",
                "New \(.applicationName) Obie",
                "Start an Obie in \(.applicationName)"
            ],
            shortTitle: "New Obie",
            systemImageName: "circle.circle"
        )
    }
}
