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
    /// Show the Obie introduction tooltip.
    ///
    /// 🚨 Was `step == 4 && obieIntroTriggered`, which was circular: this is the tip that
    /// TEACHES the Iris long-press, and it was gated on the user already performing that
    /// long-press. A new user could not discover the gesture, so they never saw the tip that
    /// explains it — and the tour ended silently at three hints (owner 2026-09-06). It now
    /// arrives with its step, like hints 1 to 3.
    var showObieIntro: Bool { step == 4 }

    /// True once every hint has been seen — the orientation has finished.
    var isComplete: Bool { step >= 5 }

    // MARK: - Transitions

    /// Kick off the tour the first time the main app is presented (post-onboarding,
    /// empty timeline). Idempotent: a no-op if the tour has already started or finished.
    func beginIfNeeded() {
        guard step == 0 else { return }
        step = 1
    }

    /// Hint 1 dismissal, and hint 2's arrival.
    ///
    /// 🚨 Called when the editor CLOSES, not when Add is tapped (owner 2026-09-06). Advancing
    /// on the tap armed hint 2 while the editor was still open, so the Iris hint appeared the
    /// instant the user pressed Add — pointing at an Iris they could not reach yet. The name
    /// is kept because the state transition is the same one; only its trigger moved.
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

    /// Hint 4 dismissal: confirming the Obie designation OR tapping elsewhere
    /// while the Obie intro is visible.
    func didDismissObieIntro() {
        guard step == 4 else { return }
        step = 5
    }

    /// Developer-only reset. Clears the persisted step so the tour runs again on
    /// next launch. FUTURE scaffolding (owner 2026-07-01: keep) — no caller yet;
    /// the Settings hook it anticipates hasn't been built.
    func resetForDeveloper() {
        step = 0
    }
}
