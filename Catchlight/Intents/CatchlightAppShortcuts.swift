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
        AppShortcut(
            intent: NewTakeIntent(),
            phrases: [
                "New Take in \(.applicationName)",
                "Add a Take to \(.applicationName)",
                "Capture a Take in \(.applicationName)",
                "New \(.applicationName) Take"
            ],
            shortTitle: "New Take",
            systemImageName: "plus.circle"
        )
    }
}
