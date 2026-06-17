//
//  InlineTakeEditCard.swift
//  Catchlight (iOS app target) — edit-in-place redesign 2026-06-17
//
//  The editable face of a Take, rendered IN POSITION on the timeline. When a Take
//  is touched it focuses (everything else masks behind it) and its read-only
//  `TakeCardSurface` is swapped for this: the same card shell (radius, padding,
//  Obie/overdue treatment) carrying live, editable block rows instead of static
//  text. Prose and check lines interleave exactly as in the (top-anchored) editor —
//  the block plumbing is the shared `BlockTextEditor` — but laid out in a plain
//  VStack so the TIMELINE'S OWN scroll carries a long Take (owner 2026-06-17:
//  "whole timeline scrolls"), rather than a nested fixed-height List.
//
//  This is the CANONICAL block editor — the top-anchored overlay editor it was
//  forked from was retired in Phase 3 (2026-06-17), so these block mutation/focus
//  helpers no longer have a duplicate. Drag-to-reorder of check items returns in a
//  follow-up increment.
//

import SwiftUI
import CatchlightCore

struct InlineTakeEditCard: View {
    @Binding var draft: Take
    @Binding var focusedBlockID: UUID?

    // MARK: - Card treatment (mirrors TakeCardSurface so read↔edit is seamless)

    private var isOverdue: Bool {
        guard let r = draft.timeReminder else { return false }
        return r.scheduledDate < Date()
    }
    private var cardSurface: Color { draft.isObie ? .ckCardObieSurface : .ckSurface }
    private var cardBorder: Color {
        if draft.isObie { return .ckCardObieBorder }
        if isOverdue { return .ckCardOverdueBorder }
        return cardSurface
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(draft.blocks) { block in
                row(for: block)
            }
        }
        // Match TakeCardSurface's v1.7 padding: 24 top (clears the overlapping Iris) /
        // 14 sides / 14 bottom; leading uses the shared text-column token.
        .padding(EdgeInsets(top: 24, leading: CatchlightLayout.cardTextLeadingPad,
                            bottom: 14, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardSurface)
                .daylightCardShadow(strong: isOverdue && !draft.isObie)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1.5)
        )
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for block: TakeBlock) -> some View {
        switch block {
        case .text(let textBlock):
            BlockTextEditor(
                blockID: textBlock.id,
                text: textBinding(textBlock.id),
                focusedBlockID: $focusedBlockID,
                isCheck: false,
                isComplete: false,
                axIdentifier: isFirstTextBlock(textBlock.id) ? "take-edit-body" : "take-edit-text",
                axLabel: "Take text",
                onBackspaceEmpty: { handleBackspaceEmpty(textBlock.id, isCheck: false) }
            )
        case .check(let item):
            HStack(alignment: .top, spacing: 8) {
                Button {
                    draft.toggleItemComplete(blockID: item.id)
                } label: {
                    Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(item.isComplete ? Color.ckAccent : Color.ckTextSecondary)
                        .frame(width: CatchlightLayout.minTouchTarget,
                               height: CatchlightLayout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("take-edit-checkbox")
                .accessibilityLabel(item.text.isEmpty ? "Checklist item" : item.text)
                .accessibilityValue(item.isComplete ? "checked" : "unchecked")
                .accessibilityHint("Double-tap to \(item.isComplete ? "untick" : "tick") this item.")
                .accessibilityAddTraits(item.isComplete ? [.isSelected, .isButton] : .isButton)

                BlockTextEditor(
                    blockID: item.id,
                    text: textBinding(item.id),
                    focusedBlockID: $focusedBlockID,
                    isCheck: true,
                    isComplete: item.isComplete,
                    axIdentifier: "take-edit-check-field",
                    axLabel: "Checklist item",
                    onReturn: { handleReturn(item.id) },
                    onBackspaceEmpty: { handleBackspaceEmpty(item.id, isCheck: true) }
                )
            }
        }
    }

    // MARK: - Bindings & block-edit helpers (canonical — the overlay editor was retired Phase 3)

    private func textBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { draft.blocks.first { $0.id == id }?.text ?? "" },
            set: { draft.updateText($0, blockID: id) }
        )
    }

    private func isFirstTextBlock(_ id: UUID) -> Bool {
        draft.blocks.first { if case .text = $0 { return true } else { return false } }?.id == id
    }

    private func handleReturn(_ id: UUID) {
        let isEmpty = (draft.blocks.first { $0.id == id }?.text ?? "").isEmpty
        if isEmpty {
            draft.convertCheckToText(blockID: id)
            focusedBlockID = id
        } else {
            focusedBlockID = draft.insertCheckItem(after: id)
        }
    }

    private func handleBackspaceEmpty(_ id: UUID, isCheck: Bool) {
        if let previous = draft.blockID(before: id) {
            draft.removeBlock(blockID: id)
            ensureNonEmpty()
            focusedBlockID = previous
        } else if isCheck {
            draft.convertCheckToText(blockID: id)
            focusedBlockID = id
        }
    }

    private func ensureNonEmpty() {
        if draft.blocks.isEmpty {
            let textBlock = TextBlock(text: "")
            draft.blocks = [.text(textBlock)]
            focusedBlockID = textBlock.id
        }
    }
}
