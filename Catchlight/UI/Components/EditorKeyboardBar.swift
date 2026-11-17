//
//  EditorKeyboardBar.swift
//  Catchlight (iOS app target) — keyboard toolbar 2026-06-19
//
//  The editing toolbar shown above the keyboard, styled to match the bottom dock (owner
//  2026-06-19): the dock's faded background (`dockFadeBackground`), so it reads as the same
//  control family rather than a plain UIKit toolbar. Hosted as the editor text view's
//  `inputAccessoryView` via a `UIHostingController` (`BlockEditorViewController.setToolbar`).
//  Its columns are laid out in `body`.
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
    /// The Important button is disabled for the Obie, which is always Important (owner
    /// 2026-10-03). It still shows, and speaks, as on.
    var importantLocked: Bool = false
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
    /// reminder-only Take) — editing the time/cadence in place, no Focus row detour.
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

    /// The plus turns into the cross once, as the bar appears (Reduce Motion: it fades in turned).
    @State private var turned = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var height: CGFloat {
        Self.panelHeight(for: dynamicTypeSize, screenWidth: UIScreen.main.bounds.width)
    }

    /// The panel's height. Lower than the Dailies bar's (`dockHeight`, 103): this one sits over
    /// the keyboard and the Take needs the room (Art Director, 2026-11-14).
    static let panelHeight: CGFloat = 76
    /// Top-aligned columns, so the icons line up when a label wraps onto a second line (Art
    /// Director 2026-11-14). This inset centres a one-line column (40 icon, 3 gap, a 16pt label)
    /// in the 76pt panel.
    static let columnTopInset: CGFloat = 8

    /// The panel's height for this text size and screen width: 76, or taller by a label line for
    /// each extra line the longest of the bar's labels wraps to in the current language ("Mark
    /// done" runs to 26 characters). The bar's host above the keyboard has a fixed height, and the editor
    /// clears the bar by it, so both read this one figure rather than the drawn panel.
    static func panelHeight(for size: DynamicTypeSize, screenWidth: CGFloat) -> CGFloat {
        // The label stays at .large (`ToolbarColumn`), and has 4pt either side in its column.
        let capped = min(size, .large)
        let traits = UITraitCollection(preferredContentSizeCategory: CatchlightFont.contentSizeCategory(capped))
        let font = UIFont.systemFont(ofSize: CatchlightFont.scaledPoints(DailiesToolbarMetrics.labelSize,
                                                                         relativeTo: .caption2,
                                                                         compatibleWith: traits),
                                     weight: .medium)
        let column = (screenWidth - 2 * CatchlightLayout.toolbarHorizontalPadding) / 4 - 8
        let labels = [String(localized: "Cancel"), String(localized: "Remind"), String(localized: "Shot List"),
                      String(localized: "Important"), String(localized: "Mark done")]
        // How many lines the longest label wraps to in its column, as the system breaks it (Thai
        // has no spaces), up to the label's three.
        let lines = labels.map { label -> CGFloat in
            let box = (label as NSString).boundingRect(with: CGSize(width: column, height: .greatestFiniteMagnitude),
                                                       options: [.usesLineFragmentOrigin],
                                                       attributes: [.font: font], context: nil)
            return min(3, max(1, (box.height / font.lineHeight).rounded()))
        }.max() ?? 1
        let content = columnTopInset + DailiesToolbarMetrics.addSquare + 3 + lines * ceil(font.lineHeight) + columnTopInset
        return max(panelHeight, ceil(content))
    }

    var body: some View {
        // The Dailies bar's format (owner 2026-11-14: "the same format and look as the main
        // toolbar"): a panel of four equal columns, each an icon over its label, no rings.
        HStack(alignment: .top, spacing: 0) {
            // 1 — Cancel: the plus turned into a cross, in the outlined square the Dailies bar
            // gives a locked Add. Quiet on purpose: it throws the edit away. Spoken as "Discard
            // changes" (owner 2026-08-16), matching the row's long-press item word for word.
            column(enabled: true, label: "Discard changes", visibleLabel: "Cancel",
                   tint: .ckTextSecondary, action: onDismiss) {
                ToolbarGlyph.plus
                    .stroke(Color.ckTextSecondary,
                            style: StrokeStyle(lineWidth: DailiesToolbarMetrics.iconStroke, lineCap: .round))
                    .frame(width: DailiesToolbarMetrics.iconSize, height: DailiesToolbarMetrics.iconSize)
                    .rotationEffect(.degrees(turned || reduceMotion ? 45 : 0))
                    .opacity(reduceMotion && !turned ? 0 : 1)
                    .onAppear {
                        withAnimation(reduceMotion ? CatchlightMotion.reduced : CatchlightMotion.turn) { turned = true }
                    }
                    .frame(width: DailiesToolbarMetrics.addSquare, height: DailiesToolbarMetrics.addSquare)
                    .overlay(CatchlightShape.control.strokeBorder(Color.ckOutline, lineWidth: 1.5))
            }

            // 2 — Remind, on both editors (audit round 9): edit the time on a reminder Take, or
            // add one, without the Focus row detour. The clock, as on the Focus row and the
            // Sequence filters. Accent when the Take has a reminder, as Important and Mark done
            // are when on (Art Director 2026-11-14: accent against secondary differs in both
            // looks, unlike the Ember-against-accent tint audit C10 removed). Falls back to a
            // greyed Shot List only where the host can't present the picker.
            if let onReminder = config.onReminder {
                column(enabled: true, identifier: "reminder-button",
                       label: config.hasReminder ? "Edit reminder" : "Add reminder", visibleLabel: "Remind",
                       tint: config.hasReminder ? .ckAccent : .ckTextSecondary, action: onReminder) {
                    ToolbarColumn.panelIcon(.clock)
                }
            } else {
                column(enabled: false, identifier: "angle-button",
                       label: "Open Shot List", visibleLabel: "Shot List",
                       tint: .ckTextComplete, action: config.onOpenAngle) {
                    shotListIcon
                }
            }

            // 3 — a task gets the Shot List here; a note keeps Important. Important leaves the
            // task bar: it stays on the Focus row and the row's long-press menu.
            if config.angleEnabled {
                column(enabled: true, identifier: "angle-button",
                       label: "Open Shot List", visibleLabel: "Shot List",
                       tint: .ckTextSecondary, action: config.onOpenAngle) {
                    shotListIcon
                }
            } else {
                // Disabled on the Obie, with a hint saying why (the SettingsRow pattern).
                column(enabled: !config.importantLocked, label: "Important", visibleLabel: "Important",
                       value: config.isImportant ? "on" : "off",
                       selected: config.isImportant,
                       hint: config.importantLocked ? "An Obie is always Important." : nil,
                       tint: config.importantLocked ? .ckTextComplete
                           : (config.isImportant ? .ckAccent : .ckTextSecondary),
                       action: config.onToggleImportant) {
                    ToolbarColumn.panelIcon(.important)
                }
            }

            // 4 — Mark done: the whole Take (every checklist item and the reminder). Greyed for
            // a pure note. The spoken label says what the tap will do; the visible one stays.
            column(enabled: config.doneEnabled,
                   label: config.isDone ? "Mark not done" : "Mark done", visibleLabel: "Mark done",
                   tint: !config.doneEnabled ? .ckTextComplete
                       : (config.isDone ? .ckAccent : .ckTextSecondary),
                   action: config.onToggleDone) {
                ToolbarColumn.panelIcon(.task)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, alignment: .top)
        .flatEdgePanel(fill: Color.ckPanel)
        // Tell the editor card where the panel's top really is, so it can keep 8pt above it.
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
            EditorBarPlacement.post(panelTop: top)
        }
        .padding(.horizontal, CatchlightLayout.toolbarHorizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .dockFadeBackground()
    }

    /// The checklist symbol: there is no `ToolbarGlyph` for the Shot List yet.
    private var shotListIcon: some View {
        Image(systemName: "checklist")
            .font(.system(size: 22, weight: .regular))
    }

    /// One column: `ToolbarColumn` (the Dailies bar's) in a button. `label` is what VoiceOver
    /// says and is unchanged from the ringed bar; `visibleLabel` is the short word under the icon.
    ///
    /// `value`/`selected` (V11, audit 2026-08): a state toggle keeps its fixed label and speaks
    /// its state as a value and the selected trait. The reminder and the tick change their label
    /// instead, on purpose: a changing label says what the button will do next.
    private func column<Glyph: View>(enabled: Bool,
                                     identifier: String? = nil,
                                     label: LocalizedStringKey,
                                     visibleLabel: LocalizedStringKey,
                                     value: LocalizedStringKey? = nil,
                                     selected: Bool = false,
                                     hint: LocalizedStringKey? = nil,
                                     tint: Color,
                                     action: @escaping () -> Void,
                                     @ViewBuilder glyph: () -> Glyph) -> some View {
        Button(action: action) {
            ToolbarColumn(icon: glyph(), label: visibleLabel, minHeight: height,
                          topInset: Self.columnTopInset)
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(identifier ?? "")
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
        .accessibilityHint(hint ?? "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Where the editor bar's panel top sits on screen, posted by the bar above the keyboard and read
/// by the editor card. The keyboard's reported frame can't stand in for it: iOS 26 reports a top
/// that includes the bar and iOS 27's final report leaves it out (measured on simulators), so a
/// card placed from the keyboard alone sat about 100pt above the bar on iOS 26.
enum EditorBarPlacement {
    static let panelTopDidChange = Notification.Name("EditorBarPanelTopDidChange")

    static func post(panelTop: CGFloat) {
        NotificationCenter.default.post(name: panelTopDidChange, object: nil, userInfo: ["top": panelTop])
    }
}
