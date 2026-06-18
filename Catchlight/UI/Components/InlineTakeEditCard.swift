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
//  helpers no longer have a duplicate. Check items reorder via a drag handle that
//  starts on touch-and-move (not a long-press, so it coexists with the card's
//  long-press menu); VoiceOver gets explicit Move up/down actions.
//

import SwiftUI
import CatchlightCore

struct InlineTakeEditCard: View {
    @Binding var draft: Take
    @Binding var focusedBlockID: UUID?
    /// Opens the full-screen Angle for this draft. INTERIM entry point (2026-06-18):
    /// the redesign moves the Angle launch to a right-side "selector ring" on every
    /// Take, but that's a device-iterated visual control built in a later supervised
    /// pass; meanwhile this top-right affordance keeps the Angle reachable for review.
    /// Shown only when an Angle applies (the list Angle applies to a checklist Take).
    var onOpenAngle: (() -> Void)? = nil

    // MARK: - Reorder drag state (touch-and-move from the handle, so it doesn't
    // collide with the card's long-press menu — owner 2026-06-17)
    /// The check item being dragged, its live finger offset, and the index it started
    /// at (fixed reference so the live reorder maths don't drift as rows shuffle).
    @State private var draggingID: UUID?
    @State private var dragOffsetY: CGFloat = 0
    @State private var dragStartIndex: Int?
    /// Approximate row height for translating drag distance → index steps. A check
    /// row is ~the 44pt touch target; tuned on device.
    private let estRowHeight: CGFloat = 44

    // MARK: - Card treatment (single-sourced with TakeCardSurface via TakeCardStyle
    // so read↔edit never drift — owner 2026-06-18). The editor mirrors the surface,
    // border, and shadow; text stays editable (not greyed) while you're in it.
    @Environment(\.colorScheme) private var scheme
    private var style: TakeCardStyle { TakeCardStyle(take: draft, scheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(draft.blocks) { block in
                row(for: block)
                    // Lift the row being dragged so it follows the finger above its
                    // neighbours while the order reflows underneath.
                    .offset(y: dragVisualOffset(for: block.id))
                    .zIndex(draggingID == block.id ? 1 : 0)
            }
        }
        // Match TakeCardSurface's v1.7 padding: 24 top (clears the overlapping Iris) /
        // 14 sides / 14 bottom; leading uses the shared text-column token.
        .padding(EdgeInsets(top: 24, leading: CatchlightLayout.cardTextLeadingPad,
                            bottom: 14, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(style.surface)
                .daylightCardShadow(strong: style.isOverdue && !draft.isObie)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style.border, lineWidth: 1.5)
        )
        // Interim top-right Angle affordance (see `onOpenAngle`). Sits in the card's
        // 24pt top padding, opposite the Iris. Shown only when an Angle applies.
        .overlay(alignment: .topTrailing) { angleAffordance }
    }

    @ViewBuilder
    private var angleAffordance: some View {
        if let onOpenAngle, let angle = AngleRegistry.applicable(to: draft).first {
            Button(action: onOpenAngle) {
                Image(systemName: angle.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ckTextSecondary)
                    .frame(width: CatchlightLayout.minTouchTarget,
                           height: CatchlightLayout.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 2)
            .accessibilityIdentifier("angle-button")
            .accessibilityLabel("Open as \(angle.title.lowercased())")
            .accessibilityHint("Shows this Take as a full-screen \(angle.title.lowercased()).")
        }
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
                onBackspaceEmpty: { handleBackspaceEmpty(textBlock.id, isCheck: false) },
                showsKeyboardGrabber: true
            )
        case .check(let item):
            HStack(alignment: .top, spacing: 8) {
                Button {
                    draft.toggleItemComplete(blockID: item.id)
                } label: {
                    // Shared glyph (owner 2026-06-18): rounded square open / ticked
                    // circle done — consistent with the list Angle.
                    TaskCheckbox(isComplete: item.isComplete)
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
                    onBackspaceEmpty: { handleBackspaceEmpty(item.id, isCheck: true) },
                    showsKeyboardGrabber: true
                )

                // Drag handle to reorder. UIKit-bridged (owner 2026-06-17, "do it
                // right"): an IMMEDIATE pan on the handle (`VerticalReorderGesture`)
                // whose delegate makes the enclosing ScrollView's pan wait for it to
                // fail — so a vertical drag that STARTS on the handle reorders at once,
                // while drags anywhere else scroll normally. No press-delay (the
                // earlier long-press version was finicky — you had to hold dead-still
                // first or it just scrolled). Holding the handle still still opens the
                // card menu; dragging it reorders. Live reflow; VoiceOver = Move actions.
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ckTextSecondary.opacity(draggingID == item.id ? 0.9 : 0.5))
                    .frame(width: CatchlightLayout.minTouchTarget,
                           height: CatchlightLayout.minTouchTarget)
                    .contentShape(Rectangle())
                    .gesture(VerticalReorderGesture(
                        onBegan: { beginReorder(item.id) },
                        onChanged: { updateReorder(item.id, translationY: $0) },
                        onEnded: { endReorder() }
                    ))
                    .accessibilityIdentifier("take-edit-reorder")
                    .accessibilityLabel("Reorder item")
                    .accessibilityAction(named: "Move up") { moveCheckItem(item.id, by: -1) }
                    .accessibilityAction(named: "Move down") { moveCheckItem(item.id, by: 1) }
            }
        }
    }

    // MARK: - Reorder (driven by the UIKit press-then-drag recognizer)

    private func beginReorder(_ id: UUID) {
        draggingID = id
        dragStartIndex = draft.blocks.firstIndex { $0.id == id }
        dragOffsetY = 0
    }

    /// `translationY` is the finger's vertical travel since the press armed. Reflow
    /// the order live each time it crosses a row-height step (fixed `dragStartIndex`
    /// reference so the maths don't drift as rows shuffle).
    private func updateReorder(_ id: UUID, translationY: CGFloat) {
        dragOffsetY = translationY
        guard let start = dragStartIndex else { return }
        let proposed = start + Int((translationY / estRowHeight).rounded())
        let target = min(max(proposed, 0), draft.blocks.count - 1)
        guard let cur = draft.blocks.firstIndex(where: { $0.id == id }), cur != target else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            let b = draft.blocks.remove(at: cur)
            draft.blocks.insert(b, at: target)
        }
    }

    private func endReorder() {
        withAnimation(.easeInOut(duration: 0.18)) {
            dragOffsetY = 0
            draggingID = nil
            dragStartIndex = nil
        }
    }

    /// Live offset that keeps the dragged row under the finger as the order reflows.
    private func dragVisualOffset(for id: UUID) -> CGFloat {
        guard draggingID == id, let start = dragStartIndex,
              let cur = draft.blocks.firstIndex(where: { $0.id == id }) else { return 0 }
        return dragOffsetY - CGFloat(cur - start) * estRowHeight
    }

    /// VoiceOver-accessible reorder — swap a check block with its neighbour. The drag
    /// handle covers touch/pointer; this backs the "Move up/down" actions on it.
    private func moveCheckItem(_ id: UUID, by offset: Int) {
        guard let i = draft.blocks.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard draft.blocks.indices.contains(j) else { return }
        draft.blocks.swapAt(i, j)
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

// MARK: - UIKit-bridged press-then-drag reorder

/// An immediate "drag the handle to reorder" gesture bridged from UIKit (iOS 18
/// `UIGestureRecognizerRepresentable`) — the same approach as `HorizontalSwipePan`,
/// and for the same reason: a SwiftUI gesture can't coordinate with the enclosing
/// ScrollView's own pan. Reorder is VERTICAL (same axis as scroll), so a velocity
/// test can't separate it — instead the delegate makes the ScrollView's pan REQUIRE
/// THIS ONE TO FAIL, so a vertical drag that starts on the handle wins outright and
/// reorders with no press-delay, while drags anywhere else scroll normally.
/// (Reused by the List Angle's reorder in Phase 4.)
struct VerticalReorderGesture: UIGestureRecognizerRepresentable {
    var onBegan: () -> Void
    /// Cumulative vertical translation (pt) since the drag began.
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let ty = recognizer.translation(in: recognizer.view).y
        switch recognizer.state {
        case .began:
            onBegan()
        case .changed:
            onChanged(ty)
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        // Begin only on a VERTICAL-led drag, so a horizontal swipe on the handle still
        // reaches the row's swipe action (orthogonal axis).
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.y) > abs(v.x)
        }

        // Make the enclosing ScrollView's pan WAIT for ours to fail — so a vertical
        // drag starting on the handle reorders instead of scrolling, with no delay.
        // Only touches on the handle involve our recognizer, so normal scrolling
        // (drags on the card body / elsewhere) is untouched.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            if let scroll = other.view as? UIScrollView, other === scroll.panGestureRecognizer {
                return true
            }
            return false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            false
        }
    }
}
