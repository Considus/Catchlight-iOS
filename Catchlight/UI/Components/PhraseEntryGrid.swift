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

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                  spacing: 10) {
            ForEach(0..<12, id: \.self) { index in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .caption))
                        .foregroundStyle(Color.ckTextSecondary)
                        .frame(width: 18, alignment: .trailing)
                    TextField("", text: $fields[index])
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.asciiCapable)
                        .submitLabel(index == 11 ? .done : .next)
                        .focused($focusedIndex, equals: index)
                        .onSubmit { focusedIndex = index < 11 ? index + 1 : nil }
                        .onChange(of: fields[index]) { _, newValue in handleChange(index, newValue) }
                        .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                        .foregroundStyle(Color.ckTextPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 9)
                        .background(Color.ckSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityIdentifier("restore-word-\(index + 1)")
                }
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
