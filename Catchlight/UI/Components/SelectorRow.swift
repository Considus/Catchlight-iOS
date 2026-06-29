//
//  SelectorRow.swift
//  Catchlight (iOS app target) — selector standardisation 2026-06-29
//
//  ONE shared visual for every "tap to choose" menu selector — leading icon, label,
//  current value, and the up/down chevron — at a standard 44pt min height. Used as
//  the label of a `Menu`/`Picker` in BOTH the Settings sheet and the reminder picker
//  so every selector reads identically. The CONTAINER (a grouped List row in Settings,
//  a rounded card in the reminder sheet) is supplied by the caller — only the row's
//  content + height live here, so the two screens can't drift.
//

import SwiftUI

struct SelectorRow: View {
    let icon: String
    let label: String
    /// The current selection, shown trailing (e.g. "System", "1 day", "Select").
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.ckAccent)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(label)
                .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                .foregroundStyle(Color.ckTextPrimary)
            Spacer(minLength: 8)
            Text(value)
                .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .subheadline))
                .foregroundStyle(Color.ckTextSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ckTextSecondary)
                .accessibilityHidden(true)
        }
        // The shared selector height (owner 2026-06-29). Grows for larger Dynamic
        // Type rather than clipping.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
