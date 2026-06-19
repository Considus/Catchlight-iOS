//
//  EditorKeyboardBar.swift
//  Catchlight (iOS app target) — keyboard toolbar 2026-06-19
//
//  The editing toolbar shown above the keyboard, styled to MATCH the bottom dock
//  (owner 2026-06-19): Ember-ringed circular buttons + the dock's faded background
//  (`dockFadeBackground`), so it reads as the same control family rather than a plain
//  UIKit toolbar. Hosted in `BlockTextEditor`'s `inputAccessoryView` via a
//  `UIHostingController`. Four buttons: ⌄ dismiss · Angle (greyed when no task) ·
//  Important · Done (tick — marks the Take done; greyed for a pure note).
//

import SwiftUI

struct EditorKeyboardBar: View {
    var config: BlockTextEditor.EditorToolbarConfig
    var onDismiss: () -> Void

    /// Matches the dock's 44pt button circle.
    private let circle: CGFloat = 44

    var body: some View {
        // FOUR EQUAL SLOTS, each glyph centred — same layout as the dock (`slotW =
        // width/4`), so the buttons sit on the dock's exact column centres (owner
        // 2026-06-19: spacing must match the bottom toolbar).
        HStack(spacing: 0) {
            // 1 — Dismiss: the dock's Add button with its "+" rotated 45° so it
            // reads as an × (owner: "the add button rotates to an X").
            slot(enabled: true, label: "Close keyboard", action: onDismiss) {
                dockSymbol("plus", tint: .ckAccent, enabled: true).rotationEffect(.degrees(45))
            }
            .frame(maxWidth: .infinity)

            // 2 — Angle (List): opens this Take's shopping list. Slot 2 to match the
            // main dock's Angle position, so it's the SAME button in the same place
            // (owner 2026-06-19). Greyed when no task applies.
            slot(enabled: config.angleEnabled, identifier: "angle-button",
                 label: "Open as list", action: config.onOpenAngle) {
                dockSymbol("bag", tint: .ckAccent, enabled: config.angleEnabled)
            }
            .frame(maxWidth: .infinity)

            // 3 — Important: the STANDARD Dailies glyph (the app's Important glyph).
            // Ember when flagged, else Ember accent.
            slot(enabled: true, label: "Important", action: config.onToggleImportant) {
                DailiesGlyph(size: 24)
                    .foregroundStyle(config.isImportant ? Color.ckEmber : Color.ckAccent)
            }
            .frame(maxWidth: .infinity)

            // 4 — Done: marks the whole Take done (all checklist items + the
            // reminder). Greyed for a pure note (nothing to complete). Was Search
            // (owner 2026-06-19 — Search did nothing useful while inside one Take).
            slot(enabled: config.doneEnabled,
                 label: config.isDone ? "Mark not done" : "Mark done",
                 action: config.onToggleDone) {
                dockSymbol(config.isDone ? "checkmark.circle.fill" : "checkmark.circle",
                           tint: config.isDone ? .ckEmber : .ckAccent,
                           enabled: config.doneEnabled)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, CatchlightLayout.dockHorizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .dockFadeBackground()
    }

    /// A dock-spec SF Symbol glyph: 24pt, .light, Ember (`ckAccent`); greys when disabled.
    private func dockSymbol(_ systemImage: String, tint: Color, enabled: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 24, weight: .light))
            .foregroundStyle(enabled ? tint : Color.ckTextSecondary.opacity(0.4))
    }

    /// One toolbar slot: the dock ring (uniform Ember @ 0.55, 1.5pt — matches
    /// `BottomDockView.dockRing`, owner 2026-06-19) with a centred glyph, in a
    /// 44pt button.
    @ViewBuilder
    private func slot<Glyph: View>(enabled: Bool,
                                   identifier: String? = nil,
                                   label: String,
                                   action: @escaping () -> Void,
                                   @ViewBuilder glyph: () -> Glyph) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color.ckAccent.opacity(0.55), lineWidth: 1.5)
                    .frame(width: circle, height: circle)
                glyph()
            }
            .frame(width: circle, height: circle)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(identifier ?? "")
        .accessibilityLabel(label)
    }
}
