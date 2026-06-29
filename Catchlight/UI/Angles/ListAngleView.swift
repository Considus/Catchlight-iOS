//
//  ListAngleView.swift
//  Catchlight (iOS app target) — Phase 3 list Angle (D-033); Phase 4 interactive list
//
//  The list Angle's presentation: the shopping-aisle view of a Take's checklist
//  — fullscreen, minimal chrome, large type, meant to be read and tapped at a
//  glance with hands full. It shows the Take's blocks in order (prose as quiet
//  context, check items large) and ticks / reorders / deletes / marks-done the SAME
//  Take through the ordinary block mutations, so every change persists and syncs
//  exactly like an edit — there is no separate state and NO text editing here (no
//  keyboard ever; renaming/adding items stays in the Dailies inline editor).
//
//  Phase 4 (owner 2026-06-17/18): each checklist item is a discrete, id-stable UNIT
//  with the full per-item interaction set — TICK (the box, ≤44pt target), REORDER
//  (drag the handle), SWIPE-LEFT to Delete, SWIPE-RIGHT to mark Done. Reorder/swipe
//  reuse the UIKit recognizers (orthogonal axes that coordinate with the scroll's
//  own pan). Completed items recede by COLOUR only (no strikethrough), matching the
//  normal Take view. Chrome is fullscreen + Dailies-style (a top fade, an X to
//  close, scroll-only — no sheet grabber).
//
//  Accessibility is by construction: each item is a single ≥44pt button exposing its
//  text, checked state and selected trait, plus named Move-up/down + Delete + Done
//  actions so every gesture has a non-gesture path.
//

import SwiftUI
import CatchlightCore

struct ListAngleView: View {
    /// The LIVE Take. Ticks / reorders / deletes mutate it in place (and persist via
    /// the host's save), so the Angle is never a separate copy of the data.
    @Binding var take: Take
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    /// The Shopping view's surface follows the Take's REAL card colour (owner
    /// 2026-06-19): light (`ckSurface`) for a normal Take, the darker emphasis
    /// surface (`ckCardObieSurface`) for an Important / Obie one. Single-sourced via
    /// `TakeCardStyle` so it can never drift from the card on the timeline.
    private var surface: Color { TakeCardStyle(take: take, scheme: scheme).surface }

    /// Single-open swipe coordination (shared with `SwipeActionRow`): opening one
    /// item's action closes any other.
    @State private var openRowID: UUID?

    // MARK: - Reorder drag state (immediate touch-and-move from the handle — the same
    // UIKit recognizer the inline editor uses, owner-approved "works great")
    @State private var draggingID: UUID?
    @State private var dragOffsetY: CGFloat = 0
    @State private var dragStartIndex: Int?

    // Row geometry. A fixed row height keeps the swipe-reveal fill exactly row-height
    // (the old maxHeight:.infinity fill drove the row taller on first layout, then
    // shrank — the "double-height then jumps the neighbours" report, owner 2026-06-18)
    // and makes the reorder step maths exact.
    private let rowHeight: CGFloat = 56
    private let rowLeadingInset: CGFloat = 16
    private let rowTrailingInset: CGFloat = 16

    var body: some View {
        // The chrome is a `.safeAreaInset` top band — an OPAQUE X-row + a 12pt fade —
        // exactly like the Dailies heading (owner 2026-06-18). Content scrolls UNDER
        // the opaque band (so it's truly masked, not just behind a translucent gradient
        // that let it peek above), and the 12pt gradient softens the dissolve edge.
        itemList
            .background(surface.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) { topChrome }
        // NOTE: no `.accessibilityIdentifier` on the container — SwiftUI merges a
        // container identifier onto shallow children. The per-element ids
        // ("angle-close" / "angle-checkbox" / "angle-reorder") are the contract.
    }

    // MARK: - Chrome (fullscreen, Dailies-style mask: opaque band + 12pt fade + an X;
    // scroll-only, no sheet grabber — owner 2026-06-18)

    private var topChrome: some View {
        VStack(spacing: 0) {
            ZStack {
                // Explicit view heading, DAILIES house style (Cormorant Roman, kerned
                // caps) — owner 2026-06-19: named as an Angle, sibling to PLANNER ANGLE.
                // CENTRED at 24pt (owner 2026-06-29) to match the timeline page heading;
                // full-width frame centres it on screen, × floated at the right edge.
                Text("SHOT LIST")
                    .font(CatchlightFont.displayRoman(size: 24, relativeTo: .title3))
                    .kerning(1.6)
                    .foregroundStyle(Color.ckTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .center)
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
                    .accessibilityLabel("Close Shot List")
                }
                .padding(.trailing, 12)
            }
            .padding(.top, 4)
            .background(surface)   // OPAQUE — content scrolls under and is hidden
            // The soft dissolve edge (matches the Dailies no-Obie heading fade).
            LinearGradient(
                colors: [surface, surface.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 12)
        }
    }

    // MARK: - The list (ScrollView + LazyVStack so the UIKit reorder/swipe recognizers
    // can coordinate with the scroll's own pan)

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(take.blocks) { block in
                    rowContainer(for: block)
                        // Lift the row being dragged so it follows the finger above its
                        // neighbours while the order reflows underneath.
                        .offset(y: dragVisualOffset(for: block.id))
                        .zIndex(draggingID == block.id ? 1 : 0)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)   // owner 2026-06-18: no scrollbar
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowContainer(for block: TakeBlock) -> some View {
        switch block {
        case .text(let textBlock):
            // Prose is quiet context: smaller, muted, non-interactive (no tick /
            // reorder / swipe — only checklist items are units).
            Text(textBlock.text)
                .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                .foregroundStyle(Color.ckTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, rowLeadingInset)
                .padding(.vertical, 8)
                .accessibilityAddTraits(.isStaticText)
        case .check(let item):
            // Swipe LEFT → Delete, swipe RIGHT → mark Done (in addition to the box tap).
            SwipeActionRow(
                id: item.id,
                leading: SwipeAction(
                    title: item.isComplete ? "Not done" : "Done",
                    systemImage: item.isComplete ? "circle" : "checkmark.circle",
                    tint: .ckAccent,
                    style: .standard,
                    perform: { toggle(item.id) }
                ),
                trailing: SwipeAction(
                    title: "Delete",
                    systemImage: "trash",
                    tint: .ckRuby,
                    style: .destructive,
                    perform: { deleteItem(item.id) }
                ),
                openRowID: $openRowID,
                leadingInset: 0,
                trailingInset: 0,
                contentVerticalInset: 0,
                tuckUnder: 0,
                actionWidth: 64,           // owner 2026-06-18: the resting Delete button read too small at 42
                centersActionLabel: true   // symmetrically surround the glyph (owner 2026-06-18)
            ) { offset in
                // Full-bleed, OPAQUE row (page-coloured) so the whole 56pt band is
                // hit-testable for the swipe pan (the timeline relies on the opaque
                // card; the Angle's rows were transparent, so the pan never fired —
                // "no swipe at all", owner 2026-06-18). It also cleanly hides the
                // action fill until it slides. Insets are 0 so the fill reaches the
                // screen edge; the row's own content is inset internally.
                checkRow(item)
                    .padding(.horizontal, rowLeadingInset)
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)
                    .background(surface)
                    .contentShape(Rectangle())
                    .offset(x: offset)
            }
            // Clamp the WHOLE swipe row to the fixed height: the action fill is
            // `maxHeight: .infinity`, so without this it stretched the row taller the
            // moment it appeared (the "double-height / neighbours jump" — owner
            // 2026-06-18, the same class we fixed on Dailies). Clamping the ZStack
            // bounds the fill to the row height.
            .frame(height: rowHeight)
        }
    }

    private func checkRow(_ item: ChecklistItem) -> some View {
        HStack(spacing: 12) {
            // TICK — the touch target is the box only (≤44pt), NOT the whole row
            // (owner 2026-06-18). Rounded square when open, ticked circle when done,
            // about half the previous glyph size.
            Button {
                toggle(item.id)
            } label: {
                TaskCheckbox(isComplete: item.isComplete)
                    .frame(width: CatchlightLayout.minTouchTarget,
                           height: CatchlightLayout.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("angle-checkbox")
            .accessibilityLabel(item.text.isEmpty ? "Item" : item.text)
            .accessibilityValue(item.isComplete ? "checked" : "unchecked")
            .accessibilityHint("Double-tap to \(item.isComplete ? "untick" : "tick") this item.")
            .accessibilityAddTraits(item.isComplete ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(named: "Move up") { moveItem(item.id, by: -1) }
            .accessibilityAction(named: "Move down") { moveItem(item.id, by: 1) }
            .accessibilityAction(named: "Delete item") { deleteItem(item.id) }

            // Item text — non-interactive; completed recedes by COLOUR only (no
            // strikethrough), matching the normal Take view (`ckTextComplete`).
            Text(item.text.isEmpty ? " " : item.text)
                .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .title3))
                .foregroundStyle(item.isComplete ? Color.ckTextComplete : Color.ckTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .accessibilityHidden(true)

            // Reorder handle — immediate vertical pan (shared with the inline editor),
            // whose delegate makes the scroll's pan wait for it to fail. Horizontal
            // drags on the handle fall through to the row's swipe (orthogonal axis).
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.ckTextSecondary.opacity(draggingID == item.id ? 0.9 : 0.4))
                .frame(width: CatchlightLayout.minTouchTarget,
                       height: CatchlightLayout.minTouchTarget)
                .contentShape(Rectangle())
                .gesture(VerticalReorderGesture(
                    onBegan: { beginReorder(item.id) },
                    onChanged: { updateReorder(item.id, translationY: $0) },
                    onEnded: { endReorder() }
                ))
                .accessibilityIdentifier("angle-reorder")
                .accessibilityLabel("Reorder item")
        }
    }

    // MARK: - Mutations

    private func toggle(_ id: UUID) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            take.toggleItemComplete(blockID: id)
        }
    }

    private func deleteItem(_ id: UUID) {
        take.removeBlock(blockID: id)
        // Never leave a Take with no blocks (an empty Take is invalid); keep one empty
        // text line so it survives as a (now blank) note.
        if take.blocks.isEmpty {
            take.blocks = [.text(TextBlock(text: ""))]
        }
    }

    /// VoiceOver-accessible reorder — swap the item with its neighbour.
    private func moveItem(_ id: UUID, by offset: Int) {
        guard let from = take.blocks.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard to >= 0, to < take.blocks.count else { return }
        take.blocks.swapAt(from, to)
    }

    // MARK: - Reorder (driven by the UIKit immediate-pan recognizer)

    private func beginReorder(_ id: UUID) {
        draggingID = id
        dragStartIndex = take.blocks.firstIndex { $0.id == id }
        dragOffsetY = 0
    }

    private func updateReorder(_ id: UUID, translationY: CGFloat) {
        dragOffsetY = translationY
        guard let start = dragStartIndex else { return }
        let proposed = start + Int((translationY / rowHeight).rounded())
        let target = min(max(proposed, 0), take.blocks.count - 1)
        guard let cur = take.blocks.firstIndex(where: { $0.id == id }), cur != target else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            let b = take.blocks.remove(at: cur)
            take.blocks.insert(b, at: target)
        }
    }

    private func endReorder() {
        withAnimation(.easeInOut(duration: 0.18)) {
            dragOffsetY = 0
            draggingID = nil
            dragStartIndex = nil
        }
    }

    private func dragVisualOffset(for id: UUID) -> CGFloat {
        guard draggingID == id, let start = dragStartIndex,
              let cur = take.blocks.firstIndex(where: { $0.id == id }) else { return 0 }
        return dragOffsetY - CGFloat(cur - start) * rowHeight
    }
}
