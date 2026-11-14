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
    let label: LocalizedStringKey
    /// The current selection, shown trailing (e.g. "System", "1 day", "Select"). Already
    /// display-ready: the caller localises it where the value is produced.
    let value: String

    var body: some View {
        // When the label and the value don't fit on one line (large text sizes, long
        // translations), the value and chevron go under the label, so the value is never cut
        // short and the label never breaks inside a word.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                iconView
                labelView
                Spacer(minLength: 8)
                valueView
            }
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                iconView
                VStack(alignment: .leading, spacing: 4) {
                    labelView
                    valueView
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        }
        // The shared selector height (owner 2026-06-29). Grows for larger Dynamic
        // Type rather than clipping.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var iconView: some View {
        Image(systemName: icon)
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(Color.ckAccent)
            .frame(width: 26)
            .accessibilityHidden(true)
    }

    private var labelView: some View {
        Text(label)
            .ckBody(.regular, size: 17, relativeTo: .body)
            .foregroundStyle(Color.ckTextPrimary)
            // A `Menu` centres a label that wraps; a long translation (or a large
            // text size) wraps here, so keep it flush left like every other row.
            .multilineTextAlignment(.leading)
    }

    private var valueView: some View {
        HStack(spacing: 8) {
            Text(value)
                .ckBody(.regular, size: 15, relativeTo: .subheadline)
                .foregroundStyle(Color.ckTextSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ckTextSecondary)
                .accessibilityHidden(true)
        }
    }
}

/// The NESTED-card menu selector — an SF-symbol label, current value, and up/down
/// chevron at the same 44pt height. The in-card sibling of `SelectorRow` (which is the
/// standalone / list-row selector). Used as a `Menu` label for the reminder Interval /
/// Days and the location Radius so every nested selector shares ONE look + height; the
/// 44 lives here once, so it can't drift (owner 2026-06-29).
struct MenuFieldRow: View {
    let title: LocalizedStringKey
    /// Optional leading SF Symbol. Omitted for borderless rows with no icon column
    /// (e.g. Cloud Storage's Sync).
    var icon: String? = nil
    /// The current selection, shown trailing.
    let value: String

    var body: some View {
        // When the title and value don't fit on one line (large text sizes, a narrow card),
        // stack them: the title above, the value and chevron below. The value stays on
        // one line in both, so it is never broken mid-word.
        ViewThatFits(in: .horizontal) {
            HStack {
                titleView
                Spacer()
                valueView
            }
            VStack(alignment: .leading, spacing: 4) {
                titleView
                valueView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .multilineTextAlignment(.leading)   // as `SelectorRow`: a Menu centres a wrapped label
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var titleView: some View {
        if let icon {
            Label(title, systemImage: icon)
                .foregroundStyle(Color.ckTextPrimary)
        } else {
            Text(title)
                .foregroundStyle(Color.ckTextPrimary)
        }
    }

    private var valueView: some View {
        HStack(spacing: 8) {
            Text(value)
                .foregroundStyle(Color.ckTextSecondary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(Color.ckTextSecondary)
        }
    }
}
