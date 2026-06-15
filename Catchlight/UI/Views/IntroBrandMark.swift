//
//  IntroBrandMark.swift
//  Catchlight (iOS app target)
//
//  The persistent brand mark — icon over wordmark — shared by the opening chapter
//  (splash · Welcome · Storage · Local warning · Reveal · Confirm · Complete) and the
//  app-entry LockView (D-042). It is drawn at an IDENTICAL position everywhere so the
//  mark reads as STATIC across crossfades and the OS launch → splash → Welcome / Lock
//  handoff never jumps.
//
//  The top inset is `deviceTopInset + 114` — i.e. 114pt below the SAFE-AREA top, not
//  the screen top. The app runs full-bleed (`.ignoresSafeArea(.container)` at the
//  root), so the `deviceTopInset` term is what keeps the mark out from under the
//  status bar / Dynamic Island (owner caught it in Daylight 2026-06-15; the dark Night
//  icon hid it). The base grew 24 → 84 → 114 (owner rule-of-thirds nudges, 2026-06-16).
//  The launch storyboard's icon-top constant is kept at the SAME 114 so the OS launch
//  handoff doesn't jump.
//
//  In onboarding this view is drawn ONCE, hoisted above the per-step crossfade in
//  `OnboardingView`, so it never fades between screens; each step reserves its space
//  with a hidden copy. The splash and LockView draw their own.
//

import SwiftUI

struct IntroBrandMark: View {
    @Environment(\.deviceTopInset) private var deviceTopInset

    var body: some View {
        VStack(spacing: 16) {
            Image("catchlight-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Image("catchlight-wordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 44)
                .accessibilityLabel("Catchlight")
        }
        .padding(.top, deviceTopInset + 114)
    }
}
