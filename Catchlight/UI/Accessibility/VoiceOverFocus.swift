//
//  VoiceOverFocus.swift
//  Catchlight (iOS app target)
//
//  One way to move the VoiceOver cursor onto something that has just appeared.
//
//  🚨 WHY THIS EXISTS. `@AccessibilityFocusState` set in the SAME update that
//  creates the element is unreliable: the request can land before the element is
//  in the accessibility tree, and SwiftUI reports nothing when it does. The
//  result is a focus move that works sometimes and is silent otherwise, which is
//  worse than one that never works — nobody goes looking for a bug that
//  intermittently behaves.
//
//  The owner met it twice. The confirm step's wrong-words warning was announced
//  on some attempts and not others (2026-09-11: "it worked previously"), and no
//  capture in eight device sessions ever recorded the automatic move, so neither
//  "it regressed" nor "it never held" could be established. The fix is the same
//  either way, which is why it was built rather than diagnosed further.
//
//  ⚠️ NOT device-verified. This is the standard workaround for the standard
//  failure, and the bench cannot check it: the simulator reports VoiceOver as
//  running and never moves a cursor (audit §15aw). It stands or falls on his
//  next pass.
//
//  🚨 EVERY CLAIM IS LOGGED, and that is not decoration. The first device round with
//  this mechanism found hints 2, 3 and 4 announcing but not taking the cursor, and
//  nothing in the capture said a focus claim had even been made — so "the claim never
//  fired" and "the claim fired and lost" were indistinguishable, and two of the three
//  are still losing to competitors nobody can name. Hint 2's was identifiable only
//  because it collided with a post that WAS logged.
//
//  📌 That is the campaign's own repeated lesson pointed at this file: an invisible
//  mechanism cannot be eliminated. `timeline.requestFocus` posted raw for six days
//  while both sessions concluded "no post precedes the fault" from a log that could
//  not contain it. This was the same shape, in newer code, written by the session that
//  recorded the lesson.
//
//  With the claim in the stream, the focus events that follow it name the winner — and
//  a named competitor gets fixed at source, as V44 was, rather than by tuning the delay
//  below until the symptom goes.
//

import SwiftUI
import UIKit

enum VoiceOverFocus {

    /// Long enough for a just-inserted element to reach the accessibility tree,
    /// and to outlast the transitions this app uses to bring one in (0.18s for
    /// the confirm warning, ~0.2s for a tour tooltip). Shorter values race the
    /// animation; longer ones are noticeable as a pause before the speech.
    static let settleDelay: TimeInterval = 0.35

    /// Run `assign` once the element has had a chance to exist.
    ///
    /// Guarded on VoiceOver actually running, for two reasons. It avoids state
    /// churn for everyone else — and more importantly, a tooltip that seizes
    /// focus is right only when there IS a cursor to seize. With VoiceOver off
    /// the call is meaningless, and running it anyway would make the behaviour
    /// harder to reason about later.
    /// - Parameter site: where the claim came from, e.g. `"tooltip.onAppear"`. Required,
    ///   not defaulted: a claim that cannot say who made it is the thing this logging exists
    ///   to stop.
    /// `@MainActor` because it reads VoiceOver's state, writes focus state and records to the
    /// diagnostics log, all of which belong on the main actor. Every caller is a SwiftUI
    /// `onAppear` / `onChange` closure, which is already there.
    @MainActor
    static func takeFocus(from site: String,
                          after delay: TimeInterval = settleDelay,
                          _ assign: @escaping @MainActor () -> Void) {
        guard UIAccessibility.isVoiceOverRunning else {
            // Logged rather than silent. Under `--a11y-diag` the recorder runs with VoiceOver
            // off, and "the claim was skipped" and "the claim was made and lost" look identical
            // in a capture that shows neither.
            A11yDiag.note("FOCUS CLAIM SKIPPED (VoiceOver off) from=\(site)")
            return
        }
        A11yDiag.note("FOCUS CLAIM from=\(site) in=\(String(format: "%.2f", delay))s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Already on main by construction; `assumeIsolated` states that to the compiler
            // rather than hopping again and moving the timing this whole type exists to control.
            MainActor.assumeIsolated {
                A11yDiag.note("FOCUS CLAIM APPLIED from=\(site)")
                assign()
            }
        }
    }
}
