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
        HStack(spacing: 0) {
            button("chevron.down", tint: .ckAccent, enabled: true,
                   label: "Close keyboard", action: onDismiss)
            Spacer(minLength: 0)
            button("exclamationmark.circle",
                   tint: config.isImportant ? .ckEmber : .ckAccent, enabled: true,
                   label: "Important", action: config.onToggleImportant)
            Spacer(minLength: 0)
            button("bag", tint: .ckAccent, enabled: config.angleEnabled,
                   identifier: "angle-button", label: "Open as list", action: config.onOpenAngle)
            Spacer(minLength: 0)
            button("magnifyingglass", tint: .ckAccent, enabled: true,
                   label: "Search", action: config.onSearch)
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
                        identifier: String? = nil,
                        label: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                // Same ring as the dock's resting buttons (Ember @35%, 1.5pt).
                Circle()
                    .strokeBorder(Color.ckAccent.opacity(0.35), lineWidth: 1.5)
                    .frame(width: circle, height: circle)
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(enabled ? tint : Color.ckTextSecondary.opacity(0.4))
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
