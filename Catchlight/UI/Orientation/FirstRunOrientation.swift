//
//  FirstRunOrientation.swift
//  Catchlight (iOS app target) — Phase 6 UI, Task 3.13
//
//  Four sequential one-time hints shown on first launch after onboarding completes.
//  Each hint is dismissed by performing the action it describes; there is no skip
//  button and no dim overlay. Step is persisted in UserDefaults under the key
//  `firstRunOrientationStep` so a fresh install gets the tour exactly once.
//
//  Step values:
//    0 — not started
//    1 — waiting for Add tap            (Hint 1: "What's your first Take?")
//    2 — waiting for Iris tap           (Hint 2: "Tap the Iris to shape this Take.")
//    3 — waiting for Settings hint      (Hint 3: "Swipe up here for settings.")
//    4 — waiting for Obie intro         (Hint 4: introduction copy)
//    5 — complete (never shown again)
//
//  The state machine only advances when the *expected* step is active. Callers may
//  fire the dismiss methods unconditionally — out-of-order calls are no-ops, so the
//  view layer doesn't have to guard every tap.
//

import SwiftUI
import Observation

@Observable
final class FirstRunOrientationState {

    static let storageKey = "firstRunOrientationStep"

    /// The current step (0…5). Mirrored to UserDefaults on every write.
    var step: Int {
        didSet {
            guard step != oldValue else { return }
            defaults.set(step, forKey: Self.storageKey)
        }
    }

    /// Hint 4 differs from 1–3: step == 4 means "armed and waiting for the user to
    /// trigger the Obie action"; the tooltip only becomes visible once they do. This
    /// flag flips on the first long-press / Obie-tap and clears on dismissal.
    private(set) var obieIntroTriggered = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Default 0 = not started. Once Dailies appears after onboarding, the
        // caller flips this to 1 via `beginIfNeeded()`.
        self.step = defaults.object(forKey: Self.storageKey) as? Int ?? 0
    }

    // MARK: - Visibility flags

    /// Show the Add-button pulse + "What's your first Take?" tooltip.
    var showAddPulse: Bool { step == 1 }
    /// Show the "Tap the Iris to shape this Take." tooltip on the first row.
    var showIrisHint: Bool { step == 2 }
    /// Show the dashed ring + "Swipe up here for settings." tooltip on the Dailies button.
    var showSettingsHint: Bool { step == 3 }
    /// Show the Obie introduction tooltip — only once the user has actually
    /// long-pressed an Iris (or tapped the Obie) while step 4 is armed.
    var showObieIntro: Bool { step == 4 && obieIntroTriggered }

    /// True once every hint has been seen — the orientation has finished.
    var isComplete: Bool { step >= 5 }

    // MARK: - Transitions

    /// Kick off the tour the first time the main app is presented (post-onboarding,
    /// empty timeline). Idempotent: a no-op if the tour has already started or finished.
    func beginIfNeeded() {
        guard step == 0 else { return }
        step = 1
    }

    /// Hint 1 dismissal: tapping the Add button.
    func didTapAdd() {
        guard step == 1 else { return }
        step = 2
    }

    /// Hint 2 dismissal: tapping a Take's Iris (TakeCircleView).
    func didTapIris() {
        guard step == 2 else { return }
        step = 3
    }

    /// Hint 3 dismissal: long-pressing the Dailies button OR tapping elsewhere
    /// while the settings hint is visible.
    func didDismissSettingsHint() {
        guard step == 3 else { return }
        step = 4
    }

    /// Arm the Obie intro tooltip — called on the user's first Obie-bound gesture
    /// (Iris long-press or Obie tap) while step 4 is waiting. No-op outside step 4.
    func triggerObieIntro() {
        guard step == 4 else { return }
        obieIntroTriggered = true
    }

    /// Hint 4 dismissal: confirming the Obie designation OR tapping elsewhere
    /// while the Obie intro is visible.
    func didDismissObieIntro() {
        guard step == 4 else { return }
        obieIntroTriggered = false
        step = 5
    }

    /// Developer-only reset (Settings hook). Clears the persisted step so the tour
    /// runs again on next launch.
    func resetForDeveloper() {
        step = 0
    }
}
