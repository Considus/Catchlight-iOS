//
//  SettingsRow.swift
//  Catchlight (iOS app target) — Phase 6 UI, Task 6.14
//
//  Reusable row used inside the Settings sheet. Three visual layers — optional
//  leading icon, label, and a trailing accessory (detail text, "Coming soon"
//  badge, chevron, custom view). Stays a dumb presentation view; the parent owns
//  the action and the gating.
//

import SwiftUI

struct SettingsRow<Accessory: View>: View {

    let icon: String?
    let label: String
    var chevron: Bool = false
    var disabled: Bool = false
    var action: (() -> Void)? = nil
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        let content = HStack(spacing: 14) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.ckAccent)
                    .frame(width: 26)
                    .accessibilityHidden(true)
            }
            Text(label)
                .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                .foregroundStyle(Color.ckTextPrimary)
            Spacer(minLength: 8)
            accessory()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ckTextSecondary)
                    .accessibilityHidden(true)
            }
        }
        // minHeight (not fixed) so the row grows at accessibility text sizes
        // instead of clipping the label or its trailing accessory.
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .opacity(disabled ? 0.38 : 1)

        Group {
            if let action, !disabled {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .listRowBackground(Color.ckSurface)
        // Compose icon + label + accessory text into a single VoiceOver element so
        // VO reads "Mode. System." rather than three separate hops. The icon is
        // already accessibilityHidden above; chevron likewise. Disabled rows ("Coming
        // soon") are non-interactive — surface a hint so VO explains why they don't
        // respond to a double-tap.
        .accessibilityElement(children: .combine)
        .accessibilityHint(disabled ? "Not available yet." : "")
    }
}

// MARK: - Convenience initialisers (no accessory / detail-only / badge-only)

extension SettingsRow where Accessory == EmptyView {
    init(icon: String? = nil,
         label: String,
         chevron: Bool = false,
         disabled: Bool = false,
         action: (() -> Void)? = nil) {
        self.init(icon: icon,
                  label: label,
                  chevron: chevron,
                  disabled: disabled,
                  action: action,
                  accessory: { EmptyView() })
    }
}

/// A small grey "Coming soon" / version-string label used as a row accessory.
struct SettingsDetailLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .subheadline))
            .foregroundStyle(Color.ckTextSecondary)
            // Truncate trailing accessory values ("Coming soon", "1.0.0", "System")
            // at the tail at large Dynamic Type sizes rather than wrapping inside
            // the row.
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

#Preview("Settings rows — Night") {
    List {
        Section { SettingsRow(icon: "moon.stars", label: "Mode") {
            SettingsDetailLabel(text: "System")
        } }
        Section { SettingsRow(icon: "paintpalette", label: "Themes", disabled: true) {
            SettingsDetailLabel(text: "Coming soon")
        } }
        Section { SettingsRow(icon: "lock", label: "PIN", chevron: true, action: {}) }
        Section { SettingsRow(icon: "info.circle", label: "About") {
            SettingsDetailLabel(text: "1.0.0")
        } }
    }
    .scrollContentBackground(.hidden)
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}
