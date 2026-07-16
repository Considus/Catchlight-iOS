//
//  TakeEditCard.swift
//  Catchlight (iOS app target) — Pillar 2 / M5b (2026-07-16)
//
//  The editing card around `BlockEditor`, in two layers so all THREE hosts share one
//  implementation without being forced into one shape:
//
//    • `TakeEditCard`      — THE CARD. `TakeCardStyle` chrome + `BlockEditor` + the creation
//                            stamp + the grow-to-a-cap height maths. Host-agnostic: it does
//                            not know where it sits or what it is anchored to.
//    • `KeyboardTakeEditor` — THE ANCHORING. Pins the card just above the keyboard and grows it
//                            UPWARD, carrying the owner-tuned descent/drop geometry.
//
//  Who uses what:
//    - `DailiesView`       → `KeyboardTakeEditor` (Iris on the spine)
//    - `StoryboardView`    → `KeyboardTakeEditor` (no Iris — no spine there, owner 2026-06-19)
//    - `LockedCaptureView` → `TakeEditCard` directly, TOP-anchored under its header (proven
//                            stable; the lock-screen capture has no timeline to sit against).
//
//  Replaces `InlineTakeEditCard` at the same seam. That view survives only for the OLD timeline
//  behind the A/B toggle, and dies with it at M7.
//

import SwiftUI
import CatchlightCore

// MARK: - The card

struct TakeEditCard: View {
    /// Single source of truth — the host owns the draft. `BlockEditor`'s coordinator mutates it
    /// only through `Take`'s block mutators, so the derived flags never drift. Hosts must GUARD
    /// the setter of any binding built from an Optional: the coordinator is UIKit and outlives
    /// the SwiftUI teardown, so a late write can resurrect a cleared draft.
    @Binding var draft: Take
    @Binding var focusedBlockID: UUID?

    /// The height past which the card stops growing and `BlockEditor` scrolls internally, so the
    /// caret can never slip behind the keyboard. The host computes it from its own geometry.
    var maxHeight: CGFloat
    /// A minimum CONTENT floor: the frame is held here while the text is short, so the caret can
    /// FALL through the reserve before the card starts growing. 0 = size straight to the content.
    var minContent: CGFloat = 0
    /// Floor for the editor frame, so a one-line Take is still a proper editing surface.
    var minEditorHeight: CGFloat = 60
    /// The Iris on the card's spine. Dailies yes; the Storyboard and the lock-screen capture have
    /// no spine.
    var showsIris: Bool = false

    var onOpenAngle: (() -> Void)? = nil
    var onEditReminder: (() -> Void)? = nil
    /// The keyboard × discards (revert); save is the host's tap-away.
    var onDiscard: (() -> Void)? = nil
    /// Tap the Iris → open the Focus-ring fan against the LIVE DRAFT (owner 2026-06-17, so the
    /// fan reflects unsaved shaping and its commit routes back to the draft — `RootView` does
    /// that routing off `ui.editingTakeID`). The `CGPoint` is the Iris centre in WINDOW coords,
    /// which is the Focus-ring overlay's space. Only meaningful with `showsIris`.
    ///
    /// Iris LONG-press is deliberately absent: it's disabled during editing (discard moved to the
    /// Take's long-press menu — owner 2026-06-17), matching the old timeline's row.
    var onTapIris: ((CGPoint) -> Void)? = nil
    /// Reports the RAW (uncapped) content height, for a host that sizes itself off it.
    var onContentHeightChange: ((CGFloat) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    /// The editor's live frame height, and the content height it last reported.
    @State private var editorHeight: CGFloat = 60
    @State private var editorContentHeight: CGFloat = 30

    /// The "Creation date" setting — the editor shows the stamp for `.editor` and `.always` (both
    /// include the editing surface), matching `InlineTakeEditCard`.
    @AppStorage(SettingsViewModel.CreationStamp.defaultsKey)
    private var creationStampRaw: String = SettingsViewModel.CreationStamp.default.rawValue
    private var creationStamp: SettingsViewModel.CreationStamp {
        SettingsViewModel.CreationStamp(rawValue: creationStampRaw) ?? .default
    }

    /// How far the editor's frame LEADS its content, so the frame is never shorter than the text
    /// (which would make `BlockEditor` scroll). Kept tiny — the owner wants the caret to sit right
    /// ON the "Created on" line, not a line above it.
    static let editorLineLead: CGFloat = 4

    /// The content height the frame should honour — the floor while short, the real content after.
    private var effectiveContent: CGFloat { max(editorContentHeight, minContent) }

    var body: some View {
        let style = TakeCardStyle(take: draft, scheme: scheme)
        let d = CatchlightLayout.circleDiameter
        let inset = CatchlightLayout.cardSpineInset
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                BlockEditor(
                    draft: $draft,
                    focusedBlockID: $focusedBlockID,
                    onOpenAngle: onOpenAngle,
                    onEditReminder: onEditReminder,
                    onDiscard: onDiscard,
                    // Only a card pinned at its cap should scroll to follow the caret; below the cap
                    // let the card GROW instead of jumping the text. Derive this from the CONTENT
                    // (does it WANT to exceed the cap?) — NOT from the current frame vs maxHeight,
                    // which flickers false whenever maxHeight shifts by a few points as the keyboard
                    // settles, wrongly telling the editor it can still grow and pinning a long
                    // Take's caret off-screen (device 2026-07-15).
                    atMaxHeight: effectiveContent + Self.editorLineLead >= maxHeight,
                    onContentHeightChange: { h in
                        editorContentHeight = h
                        onContentHeightChange?(h)
                        // Hold the frame at the floor while the text is short so the caret descends
                        // through the reserve; past that it tracks content, always leading by a hair
                        // so nothing scrolls until the cap. Any downward growth is the HOST's job
                        // (see `KeyboardTakeEditor.bottomLift`), NOT extra frame height — otherwise
                        // there'd be dead space below the caret (owner 2026-07-15).
                        let effective = max(h, minContent) + Self.editorLineLead
                        var t = Transaction(); t.disablesAnimations = true
                        withTransaction(t) {
                            editorHeight = min(max(effective, minEditorHeight), maxHeight)
                        }
                    })
                    .frame(height: editorHeight)

                // Created-at stamp, gated by the setting — Editor-only + Always both show it while
                // editing (matches `InlineTakeEditCard` so all three options stay consistent).
                if creationStamp != .off {
                    CreationStampLabel(date: draft.createdAt)
                        .padding(.top, 6)
                }
            }
            // v1.7 card text inset: 24 top (clears the overlapping Iris) / text column leading /
            // 14 bottom+trailing — matches TakeCardSurface, so read↔edit don't shift.
            .padding(EdgeInsets(top: 24, leading: CatchlightLayout.cardTextLeadingPad,
                                bottom: 14, trailing: 14))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(style.surface)
                    // A Take-card carries the same lift EVERYWHERE it is drawn (owner 2026-07-16).
                    // See the standard on `TakeCardStyle`.
                    .daylightCardShadow(strong: style.isOverdue && !draft.isObie)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style.border, lineWidth: TakeCardStyle.borderWidth)
            )

            if showsIris {
                TakeCircleView(take: draft)                              // Iris on the spine
                    .frame(width: d, height: d)
                    .shadow(color: scheme == .dark ? .clear : Color.ckInk.opacity(0.16),
                            radius: 5, y: 2)
                    // Tap → the Focus-ring fan, as on a read card. This card's Iris was purely
                    // DECORATIVE from M4.7 until 2026-07-16: on the old timeline the row's own
                    // Iris stays beside the editor and carries the gesture, so nothing was lost
                    // until M5a routed every edit through this floating card. Reuses the row's
                    // recognizer, which reports the view's centre in WINDOW coords.
                    .overlay {
                        if let onTapIris {
                            TapAndLongPressRecognizer(minimumDuration: 0.45,
                                                      onTap: onTapIris,
                                                      onLongPress: {})
                        }
                    }
                    .offset(x: inset - d / 2, y: -d / 2)
            }
        }
    }
}

// MARK: - The keyboard anchoring

/// The card pinned just above the keyboard, growing UPWARD — the timeline + Storyboard editor.
/// A NEW Take and an EXISTING-Take edit are the same card by owner decision (the M5a consistency
/// pass, 2026-07-15): a top-anchored editor ran its bottom off-screen under the keyboard ("the
/// edit-Take card has no bottom").
///
/// THE OWNER-TUNED GEOMETRY LIVES HERE AND ONLY HERE. It cost ~15 device rounds on 2026-07-15/16;
/// treat the numbers as owner decisions, not implementation detail:
///
///   1. DESCENT — the caret starts ~2 lines above its resting line and falls to just above the
///      "Created on" stamp, the card NOT yet moving (`descentFloor` holds the frame).
///   2. DROP — the card's bottom then grows DOWN by `downExpandLines` to the keyboard
///      (`bottomLift` closing to 0), so the card's bottom is actually used.
///   3. GROW UP — only then does the card grow upward, caret pinned low, older lines climbing and
///      scrolling off the top under the heading.
///   4. CAP — past `maxHeight` the card stops and `BlockEditor` scrolls internally. This is the
///      architectural fix for the caret-below-keyboard bug that returned four times.
struct KeyboardTakeEditor: View {
    @Binding var draft: Take
    @Binding var focusedBlockID: UUID?

    /// The Iris on the card's spine. Dailies yes; the Storyboard has no spine (owner 2026-06-19).
    var showsIris: Bool = true
    /// The card's left edge — the host's spine column (`spineX - cardSpineInset`).
    var leadingInset: CGFloat
    var trailingInset: CGFloat = 20

    var onOpenAngle: (() -> Void)? = nil
    var onEditReminder: (() -> Void)? = nil
    var onDiscard: (() -> Void)? = nil
    /// Tap the Iris → the Focus-ring fan at the given WINDOW-coord centre (see `TakeEditCard`).
    var onTapIris: ((CGPoint) -> Void)? = nil

    @Environment(\.deviceTopInset) private var deviceTopInset

    /// The keyboard's top edge in screen coords, INCLUDING its docked toolbar.
    @State private var keyboardTopY: CGFloat = .greatestFiniteMagnitude
    /// The card's last reported RAW content height — drives the bottom drop.
    @State private var editorContentHeight: CGFloat = 30

    /// One text line — the metric behind the descent and the downward growth.
    private static let lineH: CGFloat = 18
    /// How many lines the card's bottom drops (grows DOWN) after the descent, before it grows up.
    private static let downExpandLines: CGFloat = 2
    /// The content floor the caret descends through. One text line is ~18pt and a 1-line block is
    /// ~30pt, so 66pt ≈ room for the caret to drop two lines.
    private static let descentFloor: CGFloat = 66
    /// Keyboard + toolbar estimate, used only before the real keyboard frame arrives.
    private static let keyboardReserveFallback: CGFloat = 400
    /// The card's own top+bottom chrome, discounted from the growth allowance.
    private static let cardChrome: CGFloat = 38
    /// Inert while `descentFloor` dominates (the floor forces a taller frame regardless), but kept
    /// at the value `DailiesView` was device-validated with rather than quietly re-tuned.
    private static let minEditorHeight: CGFloat = 44

    /// How far the card's bottom is LIFTED above the keyboard right now. It stays
    /// `downExpandLines` up through the whole DESCENT (while content < the floor, the caret falling
    /// to the stamp), then closes to 0 over the next that-many lines of content — so the card's
    /// bottom drops to the keyboard only AFTER the caret has reached the bottom.
    private var bottomLift: CGFloat {
        let span = Self.lineH * Self.downExpandLines
        let phase = min(1, max(0, (editorContentHeight - Self.descentFloor) / span))
        return span * (1 - phase)
    }

    /// The grow-UP cap: how tall the card may get before its TOP reaches the heading, past which
    /// `BlockEditor` scrolls internally.
    private var maxHeight: CGFloat {
        let topLimit = deviceTopInset + CatchlightLayout.headingClearance + 12
        // Use the live keyboard top; fall back to the static estimate before it settles.
        let kbTop = keyboardTopY < UIScreen.main.bounds.height
            ? keyboardTopY
            : UIScreen.main.bounds.height - Self.keyboardReserveFallback
        return max(160, kbTop - topLimit - Self.cardChrome)
    }

    /// Bottom-anchored, riding the system keyboard. NO custom keyboard animation — it rides in sync
    /// with `BlockEditor`'s own handling (a custom rise desynced and scrolled the text off-screen,
    /// the first M5a attempt).
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            TakeEditCard(
                draft: $draft,
                focusedBlockID: $focusedBlockID,
                maxHeight: maxHeight,
                minContent: Self.descentFloor,
                minEditorHeight: Self.minEditorHeight,
                showsIris: showsIris,
                onOpenAngle: onOpenAngle,
                onEditReminder: onEditReminder,
                onDiscard: onDiscard,
                onTapIris: onTapIris,
                onContentHeightChange: { editorContentHeight = $0 }
            )
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
        }
        .padding(.bottom, max(0, UIScreen.main.bounds.height - keyboardTopY) + bottomLift)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .transition(.opacity)
        // Track the keyboard's top edge (incl. its docked toolbar). willHide reports
        // origin.y = screen height, which parks the card back at the bottom.
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            else { return }
            keyboardTopY = frame.origin.y
        }
    }
}
