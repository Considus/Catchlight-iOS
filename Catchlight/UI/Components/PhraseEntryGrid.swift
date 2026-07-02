//
//  PhraseEntryGrid.swift
//  Catchlight (iOS app target)
//
//  The 12-field privacy-phrase entry grid, shared by the onboarding restore branch
//  ("I already use Catchlight") and the Settings "Second device" flow (D-087). Owner
//  2026-07-02 (option B): twelve discrete numbered fields — explicit positions, sturdy
//  for a once-a-year action — with NO per-word validity signal (correctness is a
//  whole-phrase check on submit, matching onboarding's "reveal nothing granular"
//  posture). The parent owns the `[String]` fields and the validity/submit logic; this
//  component owns only the grid, focus, and the type-and-space / paste-spread editing.
//

import SwiftUI

struct PhraseEntryGrid: View {
    /// Twelve word fields, owned by the parent (so it can read `words`, drive the
    /// Restore button, and clear on cancel). Always length 12.
    @Binding var fields: [String]
    /// Called on every field change — the parent clears its inline error as the user edits.
    var onEdit: () -> Void = {}

    @FocusState private var focusedIndex: Int?

    /// 3×4 to mirror the onboarding Reveal/Confirm word grid exactly (owner 2026-07-02):
    /// three columns pack the 12 fields into four rows, and each cell reuses the Reveal
    /// chip's look — a `ckSurface` rounded rectangle with the daylight card shadow and a
    /// small leading number — so entry lines up with how the phrase was shown.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<12, id: \.self) { index in
                HStack(spacing: 5) {
                    Text("\(index + 1)")
                        .font(CatchlightFont.ui(.regular, size: 12, relativeTo: .caption))
                        .foregroundStyle(Color.ckTextSecondary)
                    TextField("", text: $fields[index])
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.asciiCapable)
                        .submitLabel(index == 11 ? .done : .next)
                        .focused($focusedIndex, equals: index)
                        .onSubmit { focusedIndex = index < 11 ? index + 1 : nil }
                        .onChange(of: fields[index]) { _, newValue in handleChange(index, newValue) }
                        .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                        .foregroundStyle(Color.ckTextPrimary)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("restore-word-\(index + 1)")
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.ckSurface)
                        .daylightCardShadow()
                )
            }
        }
    }

    /// Type-and-space advances to the next field; pasting a whole phrase into one field
    /// spreads it across the following fields. Words are parsed as letter-runs, so numbering
    /// / punctuation in a paste ("1. anchor 2. blossom …") is ignored.
    private func handleChange(_ index: Int, _ newValue: String) {
        onEdit()
        guard newValue.contains(where: { $0.isWhitespace || !$0.isLetter }) else { return }
        let tokens = newValue.split(whereSeparator: { !$0.isLetter }).map { $0.lowercased() }
        if tokens.count <= 1 {
            fields[index] = tokens.first ?? ""
            if !newValue.isEmpty, index < 11, tokens.count == 1,
               newValue.last.map({ $0.isWhitespace }) == true {
                focusedIndex = index + 1        // trailing space after one word → next field
            }
        } else {
            for (offset, token) in tokens.prefix(12 - index).enumerated() {
                fields[index + offset] = token   // a pasted phrase spreads across the fields
            }
            focusedIndex = min(index + tokens.count, 11)
        }
    }
}
