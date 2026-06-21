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

            // 2 — Context button at the main dock's Angle position (owner 2026-06-19/21):
            //   • a TASK → the Angle (Shot List), opening this Take's checklist;
            //   • otherwise, where the Angle would be greyed, a REMINDER button — edit
            //     the time on a reminder Take, or add one to a note, without the
            //     Focus-ring detour (owner 2026-06-21). Falls back to the greyed Angle
            //     only where the host can't present the picker (`onReminder == nil`).
            if config.angleEnabled {
                slot(enabled: true, identifier: "angle-button",
                     label: "Open Shot List", action: config.onOpenAngle) {
                    // The checklist glyph (it opens the checklist — owner 2026-06-19,
                    // matching the Angle's registered icon); sized down as it renders
                    // heavier than ∠ at the same point size.
                    dockSymbol("checklist", tint: .ckAccent, enabled: true, size: 20)
                }
                .frame(maxWidth: .infinity)
            } else if let onReminder = config.onReminder {
                slot(enabled: true, identifier: "reminder-button",
                     label: config.hasReminder ? "Edit reminder" : "Add reminder",
                     action: onReminder) {
                    dockSymbol("bell", tint: .ckAccent, enabled: true, size: 22)
                }
                .frame(maxWidth: .infinity)
            } else {
                // No task and no picker host — keep the neutral, greyed Angle.
                slot(enabled: false, identifier: "angle-button",
                     label: "Open Shot List", action: config.onOpenAngle) {
                    dockSymbol("angle", tint: .ckAccent, enabled: false, size: 24)
                }
                .frame(maxWidth: .infinity)
            }

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
                // A plain tick (no circle) — done is signalled by the Ember tint, in
                // keeping with "done = colour, not a new shape" (owner 2026-06-19).
                dockSymbol("checkmark",
                           tint: config.isDone ? .ckEmber : .ckAccent,
                           enabled: config.doneEnabled,
                           size: 22)
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
    private func dockSymbol(_ systemImage: String, tint: Color, enabled: Bool, size: CGFloat = 24) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: size, weight: .light))
            .foregroundStyle(enabled ? tint : Color.ckTextSecondary.opacity(0.4))
            // The ∠ symbol's mass sits low-left, so nudge it up to optically centre —
            // matching the main dock's Angle glyph (owner 2026-06-19).
            .offset(y: systemImage == "angle" ? -2 : 0)
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
