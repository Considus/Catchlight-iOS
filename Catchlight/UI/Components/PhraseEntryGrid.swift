//
//  PhraseEntryGrid.swift
//  Catchlight (iOS app target)
//
//  The 12-field privacy-phrase entry grid, shared by the onboarding restore branch
//  ("I already use Catchlight") and the Settings "Second device" flow (D-103). Owner
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
    /// The shared keyboard-docked accessory (Restore/Back) each field vends so the pills
    /// ride the keyboard (D-103). Supplied by the parent's `RestoreBarBridge`.
    var accessory: UIView? = nil

    /// Focus is driven by a plain index (the UIKit fields become/resign first responder
    /// from it) — not `@FocusState`, which only binds SwiftUI `TextField`s.
    @State private var focusedIndex: Int?

    /// 3×4 to mirror the onboarding Reveal/Confirm word grid exactly (owner 2026-07-02):
    /// three columns pack the 12 fields into four rows, and each cell reuses the Reveal
    /// chip's look — a `ckSurface` rounded rectangle with the daylight card shadow and a
    /// small leading number — so entry lines up with how the phrase was shown.
    /// Round 2 (owner device report 2026-09-04, items 3+4): this was a hard-coded 3, so a
    /// typed word was clipped by its cell above Large — the SAME fault DT11 fixed for the
    /// Reveal/Confirm grids, in a file that fix never touched. It now shares that helper, so
    /// entry and display give way at the same thresholds and a word you cannot check against
    /// the one you were shown never occurs.
    @Environment(\.dynamicTypeSize) private var dynamicSize
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8),
              count: phraseColumnCount(for: dynamicSize))
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<12, id: \.self) { index in
                HStack(spacing: 5) {
                    Text("\(index + 1)")
                        .font(CatchlightFont.ui(.regular, size: 12, relativeTo: .caption))
                        .foregroundStyle(Color.ckTextSecondary)
                        // V8: the field's own label now says the position, so the
                        // loose visible number is noise to assistive technology.
                        .accessibilityHidden(true)
                    PhraseTextField(text: $fields[index],
                                    index: index,
                                    focusedIndex: $focusedIndex,
                                    isLast: index == 11,
                                    accessory: accessory,
                                    onTextChange: { handleChange(index, $0) })
                        .frame(maxWidth: .infinity, minHeight: 22)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                // T7 (audit 2026-08): the cell measured ~42pt and only the inner
                // field took a touch. Floor the whole cell at 44 (adds 2pt per
                // row) and make ALL of it a target that focuses its field.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .onTapGesture { focusedIndex = index }
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
