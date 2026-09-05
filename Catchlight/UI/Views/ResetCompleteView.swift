//
//  ResetCompleteView.swift
//  Catchlight
//
//  The terminal screen after "Start over" (D-253, owner 2026-09-04).
//
//  The app has just deleted its own master key, phrase and store, so it is holding nothing it
//  can render a timeline from. Rather than quit the process — against Apple's HIG, and
//  indistinguishable from a crash to the user — it stops here and asks for a relaunch. There
//  is deliberately no button and no way back: every other screen would be reading deleted
//  state, and the next cold launch re-derives `needsOnboarding` from the absent master key
//  and lands on onboarding.
//

import SwiftUI

struct ResetCompleteView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.ckAccent)
                // The heading below carries the meaning.
                .accessibilityHidden(true)
            Text("Catchlight has been reset")
                .font(CatchlightFont.display(size: 28, relativeTo: .title2))
                .foregroundStyle(Color.ckTextPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Close Catchlight and open it again to set up a new Privacy phrase. If you exported your Takes, you can bring them back with Import from a file.")
                .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                .foregroundStyle(Color.ckTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ckBackground.ignoresSafeArea())
        // Nothing here is interactive, and nothing below it should be reachable.
        .accessibilityElement(children: .contain)
    }
}
