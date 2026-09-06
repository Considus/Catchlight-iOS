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

    /// Hint 1 dismissal, and hint 2's arrival. Called when the first Take's editor CLOSES —
    /// saved or discarded — not when Add is tapped.
    ///
    /// 🚨 Renamed from `didTapAdd()` (owner 2026-09-06). Advancing on the Add tap armed hint 2
    /// while the editor was still open, so the Iris hint appeared the instant the user pressed
    /// Add, pointing at an Iris behind the editor they had not finished with. Keeping the old
    /// name would have left a method that says "tap Add" and fires on an editor close: this
    /// campaign has twice been misled by code that reads as one thing and does another
    /// (`row(for:isFirst:)` looking like a live call site through the whole UIKit rewrite, and
    /// `triggerObieIntro()` surviving vestigial), and a name that lies is the same hazard with
    /// better odds of surviving.
    func didFinishFirstTake() {
        guard step == 1 else { return }
        step = 2
    }

    /// Hint 2 dismissal: tapping a Take's Iris (TakeCircleView).
    func didTapIris() {
        guard step == 2 else { return }
        step = 3
    }

    /// Hint 3 dismissal. Exactly two gestures, both targeted:
    ///
    ///   • a SWIPE UP on the dock — a drag of more than 30pt upward, under 60pt sideways,
    ///     starting on the button row (`BottomDockView`, the dock's DragGesture). While the
    ///     hint is up this dismisses WITHOUT opening Settings.
    ///   • a TAP on `angleNavButton` — the ∠ button specifically, which otherwise opens the
    ///     Storyboard.
    ///
    /// 🚨 A tap anywhere else does NOT dismiss it; measured on the bench 2026-09-06. This
    /// comment previously read "long-pressing the Dailies button OR tapping elsewhere", which
    /// was wrong in both halves — it is a swipe not a long-press, and one button not
    /// anywhere. That was not merely unhelpful: a peer session reasoning from it produced a
    /// plausible but false risk (that hint 4 would be consumed by the same tap that cleared
    /// hint 3) which took a bench run to disprove. Keep this list in step with the two call
    /// sites.
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
