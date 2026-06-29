//
//  LockView.swift
//  Catchlight (iOS app target) — D-042
//
//  The branded app-entry lock screen. `RootView` shows it whenever an onboarded
//  user's `AppModel.lockState` is not `.unlocked`. It replaces the old silent
//  fallback where cancelling the passcode dropped the user into a writable EMPTY
//  timeline (whose new Takes were lost on exit): here, cancelling stays on this
//  screen with a retry, and the encrypted store is bound only after a real unlock.
//
//  Auth is the device's own `.userPresence` (Face ID first, passcode fallback — the
//  OS chooses); there is no in-app PIN. The mark and its position match the
//  onboarding/splash brand mark exactly (shared `IntroBrandMark`), so a cold launch
//  reads splash → lock as one continuous surface.
//

import SwiftUI
import CatchlightCore

struct LockView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Color.ckBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                IntroBrandMark()
                // Match the onboarding mark→hero rhythm exactly (owner 2026-06-29).
                Spacer().frame(height: CatchlightLayout.introHeroTopGap)
                Text("Catchlight is locked")
                    .font(CatchlightFont.displayFixed(size: 28))
                    .foregroundStyle(Color.ckTextPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                    // Always grey, matching the onboarding subtext (owner 2026-06-29) —
                    // the error is carried by the message text + the "Try Again" button.
                    .foregroundStyle(Color.ckTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                    .padding(.horizontal, 32)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.2), value: app.lockState)
        }
        .safeAreaInset(edge: .bottom) {
            DockPillRow {
                DockPill(title: buttonTitle) { Task { await app.attemptUnlock() } }
            }
            .frame(maxWidth: .infinity)
            .dockFadeBackground()
        }
        // The auto-unlock is driven by RootView (after the splash has been seen, and
        // on a post-splash re-lock) rather than here — so the prompt never fires over
        // the splash. The Unlock / Try Again button below is the manual path.
    }

    private var message: String {
        switch app.lockState {
        case .failed(let reason): return reason
        case .unlocking:          return "Authenticating…"
        default:                  return "Authenticate to open your Takes."
        }
    }

    private var buttonTitle: String {
        switch app.lockState {
        case .failed:    return "Try Again"
        case .unlocking: return "Unlocking…"
        default:         return "Unlock"
        }
    }
}
