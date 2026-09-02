//
//  EditorKeyboardBar.swift
//  Catchlight (iOS app target) — keyboard toolbar 2026-06-19
//
//  The editing toolbar shown above the keyboard, styled to MATCH the bottom dock
//  (owner 2026-06-19): Ember-ringed circular buttons + the dock's faded background
//  (`dockFadeBackground`), so it reads as the same control family rather than a plain
//  UIKit toolbar. Hosted as the editor text view's `inputAccessoryView` via a
//  `UIHostingController` (`BlockEditorViewController.setToolbar`). Four buttons: ⌄ dismiss · Angle (greyed when no task) ·
//  Important · Done (tick — marks the Take done; greyed for a pure note).
//

import SwiftUI

// Moved out of `BlockTextEditor` at M7 (2026-07-16): the toolbar config is the TOOLBAR's,
// and the NEW UIKit editor needs it — `BlockEditor`, `BlockEditorViewController` and this
// bar all take one. Leaving it nested meant the retired SwiftUI editor could not be
// deleted without taking the live editor's toolbar with it.
/// The editing toolbar's state + actions — the Take-level context a per-block
/// editor doesn't otherwise hold. Dismiss is handled internally (clears focus).
struct EditorToolbarConfig {
    var isImportant: Bool
    /// The Angle (shopping-bag) button is enabled only when an Angle applies
    /// (a checklist Take); greyed out otherwise.
    var angleEnabled: Bool
    /// Whether the Take currently reads as done (drives the Done button's
    /// filled/active look).
    var isDone: Bool
    /// The Done (tick) button is enabled only for a task or reminder Take —
    /// a pure note can't be "done"; greyed otherwise.
    var doneEnabled: Bool
    /// Whether the Take already carries a reminder — a "when" OR a "where" (place/time
    /// parity, 2026-07-01). Drives the reminder button's "Edit reminder" vs "Add reminder"
    /// affordance (owner 2026-06-21) and, since 2026-08-16, its Ember vs accent tint.
    var hasReminder: Bool = false
    var onToggleImportant: () -> Void
    var onOpenAngle: () -> Void
    /// Open the reminder picker for THIS Take (owner 2026-06-21). When supplied,
    /// slot 2 becomes a Reminder button wherever the Angle would be greyed (a note or
    /// reminder-only Take) — editing the time/cadence in place, no Focus-ring detour.
    /// nil where the host can't present the picker (e.g. Storyboard), leaving the
    /// previous greyed-Angle behaviour.
    var onReminder: (() -> Void)? = nil
    /// Mark the whole Take done / not-done (all checklist items + the reminder).
    var onToggleDone: () -> Void
    /// The keyboard ⌄/× — DISCARD the edit and exit: the host drops the draft and the
    /// focused-edit overlay in one step, back to the timeline (or Storyboard), leaving the
    /// stored Take exactly as it was. The row's long-press "Discard changes" is the
    /// accessibility route to the same thing.
    ///
    /// It began as commit-and-exit (owner 2026-06-19) — save and drop the overlay, rather
    /// than just lowering the keyboard onto a still-focused Take — and was repurposed to
    /// discard-and-close later. This note said "saves" until 2026-08-16, describing the
    /// original job rather than the current one.
    ///
    /// Default no-op (the keyboard still resigns).
    var onDismiss: () -> Void = {}
}

struct EditorKeyboardBar: View {
    var config: EditorToolbarConfig
    var onDismiss: () -> Void

    /// Matches the dock's 44pt button circle.
    private let circle: CGFloat = 44

    var body: some View {
        // FOUR EQUAL SLOTS, each glyph centred — same layout as the dock (`slotW =
        // width/4`), so the buttons sit on the dock's exact column centres (owner
        // 2026-06-19: spacing must match the bottom toolbar).
        HStack(spacing: 0) {
            // 1 — Dismiss: the dock's Add button with its "+" rotated 45° so it
            // reads as an × (owner: "the add button rotates to an X"). Spoken as
            // "Discard changes" (owner 2026-08-16), matching the row's long-press item
            // word for word — the button throws the edit away, and "Close keyboard"
            // announced a dismissal while performing a discard.
            slot(enabled: true, label: "Discard changes", action: onDismiss) {
                dockSymbol("plus", tint: .ckAccent, enabled: true).rotationEffect(.degrees(45))
            }
            .frame(maxWidth: .infinity)

            // 2 — the REMINDER bell, on BOTH editors (audit round 9, D-239): edit
            // the time on a reminder Take, or add one, without the Focus-ring
            // detour. A task previously had NO route to its reminder at all — the
            // Angle sat here, and the ring's Reminders blade TOGGLES (one tap turns
            // the reminder off, a second creates a new one at the default offset,
            // silently discarding the time the user set), so it never edited.
            // Falls back to the greyed Angle only where the host can't present the
            // picker (`onReminder == nil`).
            //
            // NO state tint (audit C10 / D-235, supersedes D-204): the
            // Ember-vs-accent distinction never existed in Night — the two tokens
            // are the SAME hex there (1.00:1, photographed). The LABEL still
            // carries the state ("Add" vs "Edit"), per D-218.
            if let onReminder = config.onReminder {
                slot(enabled: true, identifier: "reminder-button",
                     label: config.hasReminder ? "Edit reminder" : "Add reminder",
                     action: onReminder) {
                    dockSymbol("bell", tint: .ckAccent, enabled: true, size: 22)
                }
                .frame(maxWidth: .infinity)
            } else {
                // No picker host — keep the neutral, greyed Angle.
                slot(enabled: false, identifier: "angle-button",
                     label: "Open Shot List", action: config.onOpenAngle) {
                    dockSymbol("angle", tint: .ckAccent, enabled: false, size: 24)
                }
                .frame(maxWidth: .infinity)
            }

            // 3 — a TASK gets the Shot List here (D-239: Discard · bell · Shot
            // List · Done); a note keeps Important. Important LEAVES the task
            // toolbar — it stays reachable from the Focus ring and the row's
            // long-press menu, and the four-slot bar has no fifth slot to give.
            if config.angleEnabled {
                slot(enabled: true, identifier: "angle-button",
                     label: "Open Shot List", action: config.onOpenAngle) {
                    // The checklist glyph (it opens the checklist — owner 2026-06-19,
                    // matching the Angle's registered icon); sized down as it renders
                    // heavier than ∠ at the same point size.
                    dockSymbol("checklist", tint: .ckAccent, enabled: true, size: 22)
                }
                .frame(maxWidth: .infinity)
            } else {
                // Important: the app's Important glyph, an exclamation "!".
                // NO state tint (C10 / D-235) — the VALUE below carries on/off.
                slot(enabled: true, label: "Important",
                     value: config.isImportant ? "on" : "off",
                     selected: config.isImportant,
                     action: config.onToggleImportant) {
                    ImportantGlyph(size: 24)
                        .foregroundStyle(Color.ckAccent)
                }
                .frame(maxWidth: .infinity)
            }

            // 4 — Done: marks the whole Take done (all checklist items + the
            // reminder). Greyed for a pure note (nothing to complete). Was Search
            // (owner 2026-06-19 — Search did nothing useful while inside one Take).
            slot(enabled: config.doneEnabled,
                 label: config.isDone ? "Mark not done" : "Mark done",
                 action: config.onToggleDone) {
                // A plain tick (no circle), NO state tint (C10 / D-235) — the
                // LABEL above carries done/not-done.
                dockSymbol("checkmark",
                           tint: .ckAccent,
                           enabled: config.doneEnabled,
                           size: 24)
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
    /// `value`/`selected` (V11, audit 2026-08): a STATE toggle keeps its fixed
    /// label and speaks its state as a value + the selected trait — the dock
    /// filters' pattern. (The bell and the tick change their LABEL instead,
    /// deliberately: a changing label says what the button will DO next; a value
    /// says what the state IS. Important is a state.)
    private func slot<Glyph: View>(enabled: Bool,
                                   identifier: String? = nil,
                                   label: String,
                                   value: String? = nil,
                                   selected: Bool = false,
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
        .accessibilityValue(value ?? "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
