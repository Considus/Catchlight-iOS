//
//  LockedCaptureView.swift
//  Catchlight (iOS app target) — zero-Face-ID capture (owner 2026-06-23)
//
//  Shown by RootView INSTEAD of LockView when a widget/intent capture arrived
//  while the app was locked (`AppModel.lockedCapture`). It hosts the canonical editing
//  card (`TakeEditCard`) against a brand background so the user can type the new
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

    /// A NON-optional binding into `app.lockedCapture`, mirroring `DailiesView.editDraftBinding`.
    /// `Binding($app.lockedCapture)` is a FORCE-UNWRAPPING projection: the moment the capture is
    /// committed/discarded (`lockedCapture = nil`), any read from a binding BlockEditor's coordinator
    /// still holds traps — crashing right after a save, which reads as "returned to the lock screen"
    /// (device crash logs 2026-07-16: BindingOperations.ForceUnwrapping.get). The `Take()` fallback is
    /// never shown (the view is gated on non-nil) and writes are dropped once it's gone.
    private var lockedDraftBinding: Binding<Take> {
        Binding(get: { app.lockedCapture ?? Take() },
                set: { if app.lockedCapture != nil { app.lockedCapture = $0 } })
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.ckBackground.ignoresSafeArea()

            if app.lockedCapture != nil {
                let draft = lockedDraftBinding
                // Tap the empty area to commit — text → save, blank → discard. The app's own
                // "tap the masked area" idiom. BEHIND the editor so the editor stays editable;
                // it can no longer be a spacer inside a ScrollView because `BlockEditor` does
                // its own scrolling (nesting it in one is the fight Pillar 1 exists to kill).
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { commit() }

                VStack(spacing: 0) {
                    header(isObie: draft.wrappedValue.isObie)
                    editCard(draft: draft)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    Spacer(minLength: 0)
                }
                // `BlockEditor` owns the keyboard (it reserves the overlap itself), so don't let
                // SwiftUI shove the whole stack up as well.
                .ignoresSafeArea(.keyboard, edges: .bottom)
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

    /// The editing CARD — the shared `TakeEditCard` (chrome + `BlockEditor` + creation stamp + the
    /// grow-to-a-cap height maths), which is also what the timeline and the Storyboard draw. This
    /// view held a THIRD copy of that card and its constants until 2026-07-16.
    ///
    /// TOP-anchored (under the header), NOT the keyboard-riding `KeyboardTakeEditor` the other two
    /// hosts use: the lock-screen capture has no timeline to sit against, and top-anchored is the
    /// proven-stable arrangement here. So it takes the card directly and supplies its own cap.
    /// No Iris (no spine) and no descent floor (that's a new-Take affordance on the timeline).
    private func editCard(draft: Binding<Take>) -> some View {
        TakeEditCard(
            draft: draft,
            focusedBlockID: $focusedBlockID,
            maxHeight: editorMaxHeight,
            // Keep a one-line capture a proper editing surface (`InlineTakeEditCard`'s
            // `focusMinHeight` of 96 for the whole card ≈ this, once the 24+14 padding is added).
            minEditorHeight: 60,
            // Toolbar × = DISCARD (its one job here), never save.
            onDiscard: { app.discardLockedCapture() }
        )
    }

    /// Cap the editor to the room between the header and the keyboard; beyond it `BlockEditor`
    /// scrolls internally. A STATIC keyboard estimate (as in `DailiesView`) — deriving it from the
    /// live keyboard frame makes the cap flicker as the keyboard settles.
    private var editorMaxHeight: CGFloat {
        let headerRoom = topInset + 72          // header block + its padding
        let kbReserve: CGFloat = 400            // keyboard + the editor's own toolbar (estimate)
        return max(160, UIScreen.main.bounds.height - headerRoom - kbReserve)
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
