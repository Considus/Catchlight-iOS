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

    @Environment(\.colorScheme) private var scheme

    @State private var focusedBlockID: UUID?
    @State private var unlockFailed = false

    /// The "Creation date" setting — the editor shows the stamp for `.editor` and `.always`,
    /// matching `InlineTakeEditCard` (which this view used to host) so the modes stay consistent.
    @AppStorage(SettingsViewModel.CreationStamp.defaultsKey)
    private var creationStampRaw: String = SettingsViewModel.CreationStamp.default.rawValue
    private var creationStamp: SettingsViewModel.CreationStamp {
        SettingsViewModel.CreationStamp(rawValue: creationStampRaw) ?? .default
    }
    /// The editor sizes to its content, capped to the room above the keyboard; past that
    /// `BlockEditor` scrolls internally. `editorContentHeight` is the raw (uncapped) content.
    @State private var editorHeight: CGFloat = 60
    @State private var editorContentHeight: CGFloat = 30

    /// How far the editor's frame LEADS its content, so the frame is never shorter than the
    /// text (which would make `BlockEditor` scroll instead of the card growing).
    private static let editorLineLead: CGFloat = 4

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .top) {
            Color.ckBackground.ignoresSafeArea()

            if let draft = Binding($app.lockedCapture) {
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

    /// The editing CARD: `BlockEditor` in the same shell `InlineTakeEditCard` gave this view —
    /// `TakeCardStyle` surface + border, the v1.7 padding, and the creation stamp. Single-sourced
    /// via `TakeCardStyle` so read↔edit never drift (as `DailiesView.editCardChrome` does).
    private func editCard(draft: Binding<Take>) -> some View {
        let style = TakeCardStyle(take: draft.wrappedValue, scheme: scheme)
        return VStack(alignment: .leading, spacing: 0) {
            BlockEditor(
                draft: draft,
                focusedBlockID: $focusedBlockID,
                // Toolbar × = DISCARD (its one job here), never save.
                onDiscard: { app.discardLockedCapture() },
                // Only a card at its cap should scroll to follow the caret; below it let the card
                // grow. Content-derived so it stays stable as the keyboard settles.
                atMaxHeight: editorContentHeight + Self.editorLineLead >= editorMaxHeight,
                onContentHeightChange: { h in
                    editorContentHeight = h
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) {
                        editorHeight = min(max(h + Self.editorLineLead, Self.editorMinHeight),
                                           editorMaxHeight)
                    }
                })
                .frame(height: editorHeight)

            if creationStamp != .off {
                CreationStampLabel(date: draft.wrappedValue.createdAt)
                    .padding(.top, 6)
            }
        }
        // Match TakeCardSurface's v1.7 padding, as InlineTakeEditCard did.
        .padding(EdgeInsets(top: 24, leading: CatchlightLayout.cardTextLeadingPad,
                            bottom: 14, trailing: 14))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(style.border, lineWidth: TakeCardStyle.borderWidth))
    }

    /// Keep a one-line capture a proper editing surface (InlineTakeEditCard's `focusMinHeight`
    /// of 96 for the whole card ≈ this, once the 24+14 padding is added back).
    private static let editorMinHeight: CGFloat = 60

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
