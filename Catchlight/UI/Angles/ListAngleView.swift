//
//  ListAngleView.swift
//  Catchlight (iOS app target) — Phase 3 list Angle (D-033)
//
//  The list Angle's presentation: the shopping-aisle view of a Take's checklist
//  — full-screen, minimal chrome, large type, oversized checkboxes, reorderable,
//  meant to be read and tapped at a glance with hands full. It shows the Take's
//  blocks in order (prose as quiet context, check items large) and ticks /
//  reorders the SAME Take through the ordinary block mutations, so every change
//  persists and syncs exactly like an edit — there is no separate state.
//
//  Accessibility is by construction here (this Angle IS the glanceability /
//  low-vision affordance): each item is a single ≥44pt button exposing its text,
//  checked state, and selected trait. The FORMAL VoiceOver / AX5 / Dynamic Type /
//  named-reorder sweep is Phase 4 — but it must not ship VoiceOver-broken.
//

import SwiftUI
import CatchlightCore

struct ListAngleView: View {
    /// The LIVE Take. Ticks / reorders mutate it in place (and persist via the
    /// host's save), so the Angle is never a separate copy of the data.
    @Binding var take: Take
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            itemList
        }
        .background(Color.ckBackground.ignoresSafeArea())
        // NOTE: no `.accessibilityIdentifier` on this container — SwiftUI merges a
        // container identifier onto shallow children (it overrode the close
        // button's "angle-close" with the container id). The per-element ids
        // ("angle-close" / "angle-checkbox" / "angle-reorder") are the contract.
    }

    // MARK: - Chrome (minimal: a grabber to swipe down, an explicit close)

    private var header: some View {
        ZStack {
            // Grabber: drag it down to dismiss (the shopping-aisle exit). The
            // swipe gesture is scoped to THIS sibling only — putting it on the
            // whole header would merge the close button into one a11y element and
            // hide its identifier.
            Capsule()
                .fill(Color.ckTextSecondary.opacity(0.35))
                .frame(width: 44, height: 5)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            if value.translation.height > 60 { onClose() }
                        }
                )
                .accessibilityHidden(true)

            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.ckTextSecondary)
                        .frame(width: CatchlightLayout.minTouchTarget,
                               height: CatchlightLayout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("angle-close")
                .accessibilityLabel("Close list")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    // MARK: - The list

    private var itemList: some View {
        List {
            ForEach(take.blocks) { block in
                row(for: block)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .onMove { from, to in
                take.blocks.move(fromOffsets: from, toOffset: to)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 56)
    }

    /// Move the block one step up (-1) or down (+1) — the VoiceOver-operable
    /// reorder, since drag isn't. Operates on the real Take, so it persists.
    private func moveItem(_ id: UUID, by offset: Int) {
        guard let from = take.blocks.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard to >= 0, to < take.blocks.count else { return }
        take.blocks.swapAt(from, to)
    }

    @ViewBuilder
    private func row(for block: TakeBlock) -> some View {
        switch block {
        case .text(let textBlock):
            // Prose is quiet context: smaller and muted.
            Text(textBlock.text)
                .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                .foregroundStyle(Color.ckTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .accessibilityAddTraits(.isStaticText)
        case .check(let item):
            checkRow(item)
        }
    }

    private func checkRow(_ item: ChecklistItem) -> some View {
        HStack(spacing: 16) {
            // The whole label (oversized box + big text) is one tap target.
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                    take.toggleItemComplete(blockID: item.id)
                }
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 32))
                        .foregroundStyle(item.isComplete ? Color.ckAccent : Color.ckTextSecondary)
                    Text(item.text.isEmpty ? " " : item.text)
                        // DM Sans (Take content is never the display face, DS §2.2
                        // / D-042). 17pt for the full-screen list — provisional,
                        // flagged for Phase-3 review (D-S3). Was Cormorant 26.
                        .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .title3))
                        .foregroundStyle(item.isComplete ? Color.ckTextSecondary : Color.ckTextPrimary)
                        .strikethrough(item.isComplete, color: Color.ckTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("angle-checkbox")
            .accessibilityLabel(item.text.isEmpty ? "Item" : item.text)
            .accessibilityValue(item.isComplete ? "checked" : "unchecked")
            .accessibilityHint("Double-tap to \(item.isComplete ? "untick" : "tick") this item.")
            .accessibilityAddTraits(item.isComplete ? [.isButton, .isSelected] : .isButton)
            // Drag-to-reorder is not VoiceOver-operable, so expose reorder as named
            // actions on each item (D-033 accessibility).
            .accessibilityAction(named: "Move up") { moveItem(item.id, by: -1) }
            .accessibilityAction(named: "Move down") { moveItem(item.id, by: 1) }

            // Reorder handle — List `.onMove` lifts the row on a long-press here,
            // away from the tick button. Drag fidelity is on the on-device list.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.ckTextSecondary.opacity(0.4))
                .frame(width: CatchlightLayout.minTouchTarget,
                       height: CatchlightLayout.minTouchTarget)
                .contentShape(Rectangle())
                .accessibilityIdentifier("angle-reorder")
                .accessibilityLabel("Reorder item")
        }
    }
}
