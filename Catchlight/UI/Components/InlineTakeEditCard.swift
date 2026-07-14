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
    /// Opens the full-screen Angle (the list button now lives on the keyboard
    /// toolbar, owner 2026-06-18). Shown only when an Angle applies (a checklist Take).
    var onOpenAngle: (() -> Void)? = nil
    /// Open the reminder picker for this draft (owner 2026-06-21) — slot 2 of the
    /// keyboard toolbar uses it to edit a reminder's time/cadence (or add one to a note)
    /// without the Focus-ring detour. nil where the host can't present the picker.
    var onEditReminder: (() -> Void)? = nil
    /// The keyboard toolbar's × button DISCARDS the edit (owner 2026-07-04): the
    /// host reverts the draft to its pre-edit state and drops the focused-edit
    /// overlay, saving NOTHING. Saving is the "tap blank space / another card"
    /// gesture, handled by the host — not this button. (Was `onCommit` and wired
    /// to save on the timeline/Storyboard, which contradicted the × meaning and
    /// the already-correct LockedCaptureView.)
    var onDiscard: (() -> Void)? = nil
    /// The focused block's caret rect (window coords), forwarded from the active
    /// `BlockTextEditor` so the timeline can keep it above the keyboard while a block
    /// grows (owner device report 2026-06-19). Only the focused row fires.
    var onCaretMoved: ((CGRect) -> Void)? = nil

    /// The editing toolbar's state + actions, passed to every block editor so the
    /// keyboard shows it. Angle enabled only when an Angle applies to the draft; the
    /// Done (tick) button — slot 4, replacing Search (owner 2026-06-19) — marks the
    /// whole draft done and is enabled only for a task / reminder Take.
    private var toolbarConfig: BlockTextEditor.EditorToolbarConfig {
        .init(
            isImportant: draft.isImportant,
            angleEnabled: AngleRegistry.applicable(to: draft).first != nil,
            isDone: draft.isMarkedDone,
            doneEnabled: draft.canBeMarkedDone,
            hasReminder: draft.timeReminder != nil,
            onToggleImportant: { draft.isImportant.toggle() },
            onOpenAngle: { onOpenAngle?() },
            onReminder: onEditReminder,
            onToggleDone: { draft.toggleMarkedDoneAdvancingRecurring(now: Date()) },
            onDismiss: { onDiscard?() }
        )
    }

    // MARK: - Reorder drag state (touch-and-move from the handle, so it doesn't
    // collide with the card's long-press menu — owner 2026-06-17)
    /// The check item being dragged, its live finger offset, and the index it started
    /// at (fixed reference so the live reorder maths don't drift as rows shuffle).
    @State private var draggingID: UUID?
    @State private var dragOffsetY: CGFloat = 0
    @State private var dragStartIndex: Int?
    /// Measured height of each block row, keyed by block id (owner 2026-06-21). The
    /// reorder maths use REAL heights so a dragged item lands correctly even when rows
    /// wrap to multiple lines — the editor (unlike the list Angle) doesn't line-limit, so
    /// a fixed row height under/overshot the target on wrapped items.
    @State private var rowHeights: [UUID: CGFloat] = [:]
    /// Row centre-Y positions captured at drag start (the stable reference the live
    /// reorder maps the finger against, so it doesn't drift as rows reflow).
    @State private var dragStartCenters: [CGFloat] = []
    /// Fallback height for a row not yet measured (matches the 44pt touch target).
    private let estRowHeight: CGFloat = 44
    /// Matches the editor `VStack(spacing:)`, so the measured centres line up with layout.
    private let rowSpacing: CGFloat = 2

    // MARK: - Card treatment (single-sourced with TakeCardSurface via TakeCardStyle
    // so read↔edit never drift — owner 2026-06-18). The editor mirrors the surface,
    // border, and shadow; text stays editable (not greyed) while you're in it.
    @Environment(\.colorScheme) private var scheme
    private var style: TakeCardStyle { TakeCardStyle(take: draft, scheme: scheme) }

    /// A fixed minimum height for the focused editing card (owner 2026-06-19), so a
    /// one-line Take is still a proper editing surface and every focused Take is a
    /// consistent target — steadier to position above the keyboard. Tunable.
    private let focusMinHeight: CGFloat = 96

    /// The "Creation date" setting — the editor shows the stamp for `.editor` and `.always`
    /// (both include the editing surface). See `CreationStampLabel`.
    @AppStorage(SettingsViewModel.CreationStamp.defaultsKey)
    private var creationStampRaw: String = SettingsViewModel.CreationStamp.default.rawValue
    private var creationStamp: SettingsViewModel.CreationStamp {
        SettingsViewModel.CreationStamp(rawValue: creationStampRaw) ?? .default
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(draft.blocks) { block in
                row(for: block)
                    // Tagged so the pinned focus overlay's ScrollViewReader can scroll
                    // the focused block into view on a long Take (owner 2026-06-19).
                    .id(block.id)
                    // Measure the row's natural height (before the drag offset) so the
                    // reorder maths know the real geometry of wrapped multi-line rows.
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: RowHeightKey.self,
                                               value: [block.id: proxy.size.height])
                    })
                    // Lift the row being dragged so it follows the finger above its
                    // neighbours while the order reflows underneath.
                    .offset(y: dragVisualOffset(for: block.id))
                    .zIndex(draggingID == block.id ? 1 : 0)
            }

            // Created-at stamp at the bottom of the editing card, shown when the
            // "Creation date" setting is Editor-only or Always (owner 2026-07-01).
            if creationStamp != .off {
                CreationStampLabel(date: draft.createdAt)
                    .padding(.top, 6)
            }
        }
        .onPreferenceChange(RowHeightKey.self) { rowHeights = $0 }
        // Match TakeCardSurface's v1.7 padding: 24 top (clears the overlapping Iris) /
        // 14 sides / 14 bottom; leading uses the shared text-column token.
        .padding(EdgeInsets(top: 24, leading: CatchlightLayout.cardTextLeadingPad,
                            bottom: 14, trailing: 14))
        .frame(maxWidth: .infinity, minHeight: focusMinHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(style.surface)
                .daylightCardShadow(strong: style.isOverdue && !draft.isObie)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style.border, lineWidth: TakeCardStyle.borderWidth)
        )
        // (The interim top-right Angle button was retired 2026-06-18 — the Angle now
        // lives as the shopping-bag button on the keyboard toolbar.)
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
                toolbar: toolbarConfig,
                onCaretMoved: onCaretMoved
            )
        case .check(let item):
            // CENTRE-aligned to match the Shot List (owner 2026-06-18): the glyph is
            // centred in its 44pt frame, so centring the row lines it up with the
            // item's line. `.top` made the centred glyph sit ~8pt below the text's
            // first line (text inset 6 + half-line vs half of 44) — the "text higher
            // than the checkbox" the owner spotted. Scales with Dynamic Type for the
            // common single-line item.
            HStack(alignment: .center, spacing: 8) {
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
                    toolbar: toolbarConfig,
                    onCaretMoved: onCaretMoved
                )
                // Nudge just the item TEXT down ~2pt (owner 2026-07-02): the checkbox and
                // drag handle centre correctly, but a line's optical centre rides above
                // its line-box centre, so the words read a touch high next to the boxes.
                // Visual only (`.offset`), so it doesn't change the row height.
                .offset(y: 2)

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
        // Snapshot the resting row centres (real measured heights) as the fixed reference
        // the live reorder maps the finger against.
        let heights = draft.blocks.map { rowHeights[$0.id] ?? estRowHeight }
        dragStartCenters = Self.rowCenters(heights: heights, spacing: rowSpacing)
        dragOffsetY = 0
    }

    /// `translationY` is the finger's vertical travel since the press armed. Reflow the
    /// order live: the dragged row's centre is `startCentre + translationY`, and its target
    /// slot is the row whose resting centre is nearest — so a drag over wrapped, taller
    /// rows lands where the finger actually is, not where a fixed row height guessed.
    private func updateReorder(_ id: UUID, translationY: CGFloat) {
        dragOffsetY = translationY
        guard let start = dragStartIndex else { return }
        let target = Self.reorderTarget(centers: dragStartCenters, start: start, translationY: translationY)
        guard let cur = draft.blocks.firstIndex(where: { $0.id == id }), cur != target,
              draft.blocks.indices.contains(target) else { return }
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
            dragStartCenters = []
        }
    }

    /// Live offset that keeps the dragged row under the finger as the order reflows —
    /// the finger's absolute Y (from the start snapshot) minus the dragged row's CURRENT
    /// resting centre, both from real heights.
    private func dragVisualOffset(for id: UUID) -> CGFloat {
        guard draggingID == id, let start = dragStartIndex,
              start < dragStartCenters.count,
              let cur = draft.blocks.firstIndex(where: { $0.id == id }) else { return 0 }
        let fingerAbsY = dragStartCenters[start] + dragOffsetY
        let currentHeights = draft.blocks.map { rowHeights[$0.id] ?? estRowHeight }
        let currentCenters = Self.rowCenters(heights: currentHeights, spacing: rowSpacing)
        guard cur < currentCenters.count else { return 0 }
        return fingerAbsY - currentCenters[cur]
    }

    // MARK: - Reorder geometry (pure — unit-tested without a view)

    /// The centre-Y of each stacked row, given each row's height and the inter-row spacing.
    static func rowCenters(heights: [CGFloat], spacing: CGFloat) -> [CGFloat] {
        var centers: [CGFloat] = []
        var y: CGFloat = 0
        for h in heights {
            centers.append(y + h / 2)
            y += h + spacing
        }
        return centers
    }

    /// The index of the row whose resting centre is nearest the dragged row's live centre
    /// (`centers[start] + translationY`). Falls back to `start` when the snapshot is empty.
    static func reorderTarget(centers: [CGFloat], start: Int, translationY: CGFloat) -> Int {
        guard start >= 0, start < centers.count else { return start }
        let fingerCenter = centers[start] + translationY
        var best = start
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, centre) in centers.enumerated() {
            let distance = abs(centre - fingerCenter)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
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
/// (Reused by the Shot List's reorder in Phase 4.)
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

/// Collects each block row's measured height (keyed by block id) so the reorder maths
/// use real geometry. Last writer wins per id; the dict merges across all rows.
private struct RowHeightKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
