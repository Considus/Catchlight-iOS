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
    static func takeFocus(after delay: TimeInterval = settleDelay,
                          _ assign: @escaping () -> Void) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: assign)
    }
}
