//
//  EditorKeyboardBar.swift
//  Catchlight (iOS app target) — keyboard toolbar 2026-06-19
//
//  The editing toolbar shown above the keyboard, styled to MATCH the bottom dock
//  (owner 2026-06-19): Ember-ringed circular buttons + the dock's faded background
//  (`dockFadeBackground`), so it reads as the same control family rather than a plain
//  UIKit toolbar. Hosted in `BlockTextEditor`'s `inputAccessoryView` via a
//  `UIHostingController`. Four buttons: ⌄ dismiss · Important · Angle (greyed when no
//  task) · Search.
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
            // Dismiss = the dock's Add button (strong ring) with its "+" rotated 45°
            // so it reads as an × (owner 2026-06-19: "the add button rotates to an X").
            button("plus", tint: .ckAccent, enabled: true, strong: true, rotate: 45,
                   label: "Close keyboard", action: onDismiss)
                .frame(maxWidth: .infinity)
            button("exclamationmark.circle",
                   tint: config.isImportant ? .ckEmber : .ckAccent, enabled: true,
                   label: "Important", action: config.onToggleImportant)
                .frame(maxWidth: .infinity)
            button("bag", tint: .ckAccent, enabled: config.angleEnabled,
                   identifier: "angle-button", label: "Open as list", action: config.onOpenAngle)
                .frame(maxWidth: .infinity)
            button("magnifyingglass", tint: .ckAccent, enabled: true,
                   label: "Search", action: config.onSearch)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, CatchlightLayout.dockHorizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .dockFadeBackground()
    }

    @ViewBuilder
    private func button(_ systemImage: String,
                        tint: Color,
                        enabled: Bool,
                        strong: Bool = false,
                        rotate: Double = 0,
                        identifier: String? = nil,
                        label: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                // Match the dock's ring: Ember @55% (Add) / @35% (others), 1.5pt.
                Circle()
                    .strokeBorder(Color.ckAccent.opacity(strong ? 0.55 : 0.35), lineWidth: 1.5)
                    .frame(width: circle, height: circle)
                // Match the dock's navIcon glyph: 24pt, .light, Ember (ckAccent).
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(enabled ? tint : Color.ckTextSecondary.opacity(0.4))
                    .rotationEffect(.degrees(rotate))
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
