//
//  LockedCaptureView.swift
//  Catchlight (iOS app target) — zero-Face-ID capture (owner 2026-06-23)
//
//  Shown by RootView INSTEAD of LockView when a widget/intent capture arrived
//  while the app was locked (`AppModel.lockedCapture`). It hosts the canonical
//  `InlineTakeEditCard` against a brand background so the user can type the new
//  Take (or Obie) IMMEDIATELY — "one glance → type" — with NO app-lock prompt
//  first. The store is still the empty in-memory placeholder, so no existing
//  Take content is loaded or visible here.
//
//  TWO affordances, one job each (owner 2026-06-23):
//    • TAP AWAY (the empty area) → commit: text → save (the single Face ID fires
//      here, in saveLockedCapture); blank → discard back to the lock screen. This
//      is the timeline's "tap the masked area to commit" idiom.
//    • TOOLBAR × → always DISCARD — the way to ditch text you've decided not to
//      keep. Never saves.
//
//  The editor binds DIRECTLY to `app.lockedCapture` (the observed source of truth),
//  so the typed text is always what `saveLockedCapture` reads — no view-local copy
//  that could lag behind.
//

import SwiftUI
import CatchlightCore

struct LockedCaptureView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.deviceTopInset) private var topInset

    @State private var focusedBlockID: UUID?
    @State private var unlockFailed = false

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .top) {
            Color.ckBackground.ignoresSafeArea()

            if let draft = Binding($app.lockedCapture) {
                VStack(spacing: 0) {
                    header(isObie: draft.wrappedValue.isObie)
                    ScrollView {
                        VStack(spacing: 0) {
                            InlineTakeEditCard(
                                draft: draft,
                                focusedBlockID: $focusedBlockID,
                                // Toolbar × = DISCARD (its one job here), never save.
                                onCommit: { app.discardLockedCapture() }
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                            // Tap the empty area to commit — text → save, blank → discard.
                            // The app's own "tap the masked area" idiom.
                            Color.clear
                                .frame(minHeight: 500)
                                .contentShape(Rectangle())
                                .onTapGesture { commit() }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .onAppear {
            // Focus the first block so the keyboard comes up — deferred so the editor
            // is in the window and the 0.4s fade-in settles before the keyboard rises.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedBlockID = app.lockedCapture?.blocks.first?.id
            }
        }
    }

    private func header(isObie: Bool) -> some View {
        VStack(spacing: 6) {
            // Orientation only — the × (discard) and tap-away (save) carry the actions.
            Text(isObie ? "New Obie" : "New Take")
                .font(CatchlightFont.ui(.medium, size: 17, relativeTo: .headline))
                .foregroundStyle(Color.ckTextPrimary)

            if unlockFailed {
                Text("Couldn't unlock — tap to save again.")
                    .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.ckTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, topInset + 12)
        .padding(.bottom, 4)
    }

    private func commit() {
        Task {
            await app.saveLockedCapture()
            // Still locked afterwards ⇒ the unlock was cancelled/failed. Keep the text,
            // flag a retry, and re-raise the keyboard so a tap-away can try again.
            if app.lockedCapture != nil {
                unlockFailed = true
                focusedBlockID = app.lockedCapture?.blocks.first?.id
            }
        }
    }
}
