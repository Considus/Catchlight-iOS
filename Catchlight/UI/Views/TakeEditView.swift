//
//  TakeEditView.swift
//  Catchlight (iOS app target) — Phase 6 UI / Phase 2 block editor (D-035)
//
//  Creating / editing a Take. A card that rises into the upper third of the
//  screen above a dimmed background. The writing surface is a BLOCK-STACK
//  editor: an ordered list of rows where prose lines and checkbox lines
//  interleave inline (Apple Notes / Word parity), replacing the old single
//  TextEditor. The footer keeps the Take's Iris + "Shape this take" (the Focus
//  ring); auto-saves on dismiss; there is no explicit save button.
//
//  Interaction (see BlockTextEditor for the UITextView plumbing):
//    • Type prose in a text row; Return is a normal newline.
//    • Focus-ring "Task" Mark ON → existing prose is kept as-is and ONE empty
//      check item is added (the first task entry), with focus dropped into it so
//      the user types immediately. OFF → check items join back into prose.
//    • Return in a non-empty check row continues the list; Return in an EMPTY
//      check row exits back to prose. Backspace on an empty row merges upward.
//    • Tap a checkbox to tick; drag (the trailing handle) to reorder; swipe to
//      delete.
//
//  Focus/cursor management across rows is the fiddly part and only fully
//  exercises on a device — the simulator does not reproduce all keyboard timing.
//

import SwiftUI
import CatchlightCore

struct TakeEditView: View {
    @Environment(DailiesViewModel.self) private var vm
    @Environment(UIState.self) private var ui
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme

    let take: Take

    /// The live, editable Take. The single source of truth while the editor is
    /// open; persisted on dismiss. Activity flags / reminder ride here too so a
    /// Focus-ring commit applies to what's on screen, not the stored copy.
    @State private var draft: Take
    /// Which block holds the keyboard. Driven across rows on Return / Backspace /
    /// make-checklist; bound into each row's BlockTextEditor.
    @State private var focusedBlockID: UUID?
    /// The Angle (D-033) currently presented full-screen over the editor, if any.
    @State private var presentedAngle: Angle?

    init(take: Take) {
        self.take = take
        _draft = State(initialValue: Self.normalisedForEditing(take))
    }

    /// A Take always edits with at least one row; a brand-new (blocks-empty) Take
    /// gets one empty prose row to type into. The empty row is pruned on save.
    private static func normalisedForEditing(_ take: Take) -> Take {
        var t = take
        if t.blocks.isEmpty { t.blocks = [.text(TextBlock(text: ""))] }
        return t
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Dim background — tap to save + dismiss.
            Color.ckDim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { saveAndDismiss() }
                .accessibilityIdentifier("editor-done")
                .accessibilityLabel("Done editing")
                .accessibilityHint("Double-tap to save this Take and close.")
                .accessibilityAddTraits(.isButton)

            card
                .padding(.horizontal, 16)
                // Standard first-row position (cosmetic baseline 2026-06-11):
                // the card sits where the top Take sits, below the (veiled)
                // heading — not hugging the very top of the screen.
                .padding(.top, 56)
        }
        .onAppear {
            if focusedBlockID == nil { focusedBlockID = draft.blocks.first?.id }
        }
        .onChange(of: ui.editorFanCommand) { _, command in
            // The Focus ring committed while this editor is open — apply it to
            // the live draft (the Task Mark reshapes the on-screen blocks).
            guard let command else { return }
            applyFanCommand(command)
            ui.editorFanCommand = nil
        }
        // The Angle is an ephemeral, full-screen toggle over the editor. It binds
        // to the LIVE draft, so its ticks / reorders ride the editor's own save
        // on dismiss — exactly like an edit, no separate state. iOS already swaps
        // the cover's slide for a fade under Reduce Motion.
        .fullScreenCover(item: $presentedAngle) { angle in
            angle.makePresentation($draft) { presentedAngle = nil }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            blockList
                .padding(.top, 6)

            Divider().background(Color.ckTextSecondary.opacity(0.2))

            footer
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.ckSurface)
                .shadow(color: Color.ckShadow.opacity(0.5), radius: 18, y: 6)
        )
        // The Angle affordance sits at the top-right of the Take, mirroring the
        // footer Iris on the opposite corner (placement per spec §6; flagged for
        // owner review against the HiFi). Shown only when an Angle applies.
        .overlay(alignment: .topTrailing) {
            angleAffordance
                .padding(.top, 6)
                .padding(.trailing, 6)
        }
    }

    // MARK: - Angle affordance (D-033)

    @ViewBuilder
    private var angleAffordance: some View {
        let angles = AngleRegistry.applicable(to: currentTake)
        if angles.count == 1, let angle = angles.first {
            angleButton(systemImage: angle.systemImage,
                        label: "View as \(angle.title)") { openAngle(angle) }
        } else if angles.count > 1 {
            // More than one Angle applies → a small picker (Day 1 never hits this,
            // but the system is built for it).
            Menu {
                ForEach(angles) { angle in
                    Button { openAngle(angle) } label: {
                        Label(angle.title, systemImage: angle.systemImage)
                    }
                }
            } label: {
                angleIcon(systemImage: "square.on.square")
            }
            .accessibilityIdentifier("angle-button")
            .accessibilityLabel("Choose a view")
        }
    }

    private func angleButton(systemImage: String, label: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) { angleIcon(systemImage: systemImage) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("angle-button")
            .accessibilityLabel(label)
            .accessibilityHint("Opens a full-screen list view of this Take.")
    }

    private func angleIcon(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.ckAccent)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.ckSurface))
            .overlay(Circle().stroke(Color.ckAccent.opacity(0.4), lineWidth: 1))
            .frame(width: CatchlightLayout.minTouchTarget,
                   height: CatchlightLayout.minTouchTarget)
            .contentShape(Rectangle())
    }

    private func openAngle(_ angle: Angle) {
        focusedBlockID = nil   // drop the keyboard before the cover presents
        presentedAngle = angle
    }

    // MARK: - Block stack

    // A `List` of block rows. List is used deliberately over a ScrollView/VStack:
    // it manages its OWN keyboard avoidance internally (scrolling the focused row
    // into view without shoving the whole top-anchored card down to mid-screen —
    // which a ScrollView did on iOS 17, breaking tap-outside-to-dismiss), and it
    // sizes each UITextView row reliably. The earlier List focus/render loop on
    // block-restructure is prevented by the coordinator's `focusRequested` latch
    // (BlockTextEditor) plus per-row identity by block id. `.onMove` reorders.
    //
    // No `.accessibilityIdentifier` on the List — on iOS 17 SwiftUI merges a
    // container identifier onto a lone child, overriding the per-row
    // "take-edit-body" / "take-edit-check-field" ids the tests query.
    private var blockList: some View {
        List {
            ForEach(draft.blocks) { block in
                row(for: block)
                    .listRowInsets(EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 6))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .onMove { from, to in
                draft.blocks.move(fromOffsets: from, toOffset: to)
            }
            .onDelete { offsets in
                draft.blocks.remove(atOffsets: offsets)
                ensureNonEmpty()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 36)
        .frame(minHeight: 160, maxHeight: 280)
    }

    @ViewBuilder
    private func row(for block: TakeBlock) -> some View {
        switch block {
        case .text(let textBlock):
            textRow(textBlock)
        case .check(let item):
            checkRow(item)
        }
    }

    private func textRow(_ textBlock: TextBlock) -> some View {
        BlockTextEditor(
            blockID: textBlock.id,
            text: textBinding(textBlock.id),
            focusedBlockID: $focusedBlockID,
            isCheck: false,
            isComplete: false,
            // The first prose row keeps the historical id the create/edit flows
            // type into ("take-edit-body"); later prose rows get a generic id.
            axIdentifier: isFirstTextBlock(textBlock.id) ? "take-edit-body" : "take-edit-text",
            axLabel: "Take text",
            onBackspaceEmpty: { handleBackspaceEmpty(textBlock.id, isCheck: false) }
        )
    }

    private func checkRow(_ item: ChecklistItem) -> some View {
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

            // 44pt drag affordance. The List's `.onMove` lifts the row on a
            // long-press from this non-editable handle (it doesn't fight the text
            // view's gestures). Drag fidelity is on the on-device verification list.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ckTextSecondary.opacity(0.5))
                .frame(width: CatchlightLayout.minTouchTarget,
                       height: CatchlightLayout.minTouchTarget)
                .contentShape(Rectangle())
                .accessibilityIdentifier("take-edit-reorder")
                .accessibilityLabel("Reorder item")
        }
    }

    // MARK: - Row bindings & helpers

    private func textBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { draft.blocks.first { $0.id == id }?.text ?? "" },
            set: { draft.updateText($0, blockID: id) }
        )
    }

    private func isFirstTextBlock(_ id: UUID) -> Bool {
        draft.blocks.first { if case .text = $0 { return true } else { return false } }?.id == id
    }

    /// Return inside a check row: continue the list, or exit to prose when empty.
    private func handleReturn(_ id: UUID) {
        let isEmpty = (draft.blocks.first { $0.id == id }?.text ?? "").isEmpty
        if isEmpty {
            draft.convertCheckToText(blockID: id)   // exit the list (rule 4)
            focusedBlockID = id                      // …staying in the now-prose row
        } else {
            focusedBlockID = draft.insertCheckItem(after: id)  // continue (rule 3)
        }
    }

    /// Backspace on an empty row: merge with the block above, or — for the first
    /// check row — exit the list back to prose.
    private func handleBackspaceEmpty(_ id: UUID, isCheck: Bool) {
        if let previous = draft.blockID(before: id) {
            draft.removeBlock(blockID: id)
            ensureNonEmpty()
            focusedBlockID = previous
        } else if isCheck {
            draft.convertCheckToText(blockID: id)
            focusedBlockID = id
        }
        // Empty first prose row + backspace: nothing to merge into.
    }

    private func ensureNonEmpty() {
        if draft.blocks.isEmpty {
            let textBlock = TextBlock(text: "")
            draft.blocks = [.text(textBlock)]
            focusedBlockID = textBlock.id
        }
    }

    /// Apply a Focus-ring selection to the live draft. The Task Mark is
    /// structural (reshapes blocks); Note / Reminder / Obie are activity flags.
    private func applyFanCommand(_ command: UIState.EditorFanCommand) {
        draft.isNote = command.isNote

        if command.isTask && !draft.isTask {
            // Turn ON: keep existing prose, add one empty check item, drop focus in
            // (owner 2026-06-17 — Task no longer eats the lines already written).
            let firstItem = draft.convertToChecklist()
            focusedBlockID = firstItem ?? draft.checkItems.first?.id
        } else if !command.isTask && draft.isTask {
            draft.convertToProse()
        }

        if command.hasReminder, draft.timeReminder == nil {
            // Mirror DailiesViewModel.applyActivityTypes: default to tomorrow; the
            // reminder surface refines it.
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            draft.timeReminder = TimeReminder(scheduledDate: tomorrow,
                                              notificationIdentifier: draft.id.uuidString)
        } else if !command.hasReminder {
            draft.timeReminder = nil
        }

        draft.isObie = command.isObie
        draft.normaliseActivityFloor()
    }

    // MARK: - Footer (Iris + Shape this take)

    private var footer: some View {
        HStack(spacing: 12) {
            // The footer Iris (UX §19): TAP opens the Focus ring (shape); LONG-PRESS
            // discards a content-ful Take. The × in the centre void is a VISUAL
            // affordance only — the spec deliberately routes discard through
            // long-press, never a tap on the ×, "too small to tap reliably". Shown
            // only when there's content to abandon (an empty Take is silently
            // dropped by a tap outside). The Iris is 44pt to match the timeline +
            // give the × room (owner 2026-06-15).
            ZStack {
                TakeCircleView(take: currentTake, diameter: CatchlightLayout.circleDiameter)
                if draftHasContent {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.ckAccent)   // Ember/#856539, the toolbar treatment (D-028)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: CatchlightLayout.circleDiameter, height: CatchlightLayout.circleDiameter)
            .frame(minWidth: CatchlightLayout.minTouchTarget,
                   minHeight: CatchlightLayout.minTouchTarget)
            .contentShape(Rectangle())
            .overlay(
                TapAndLongPressRecognizer(
                    minimumDuration: 0.45,
                    onTap: { _ in ui.openPetalFan(for: currentTake) },
                    onLongPress: { discardAndDismiss() }
                )
            )
            .accessibilityElement()
            .accessibilityIdentifier("editor-shape")
            .accessibilityLabel("Shape this Take. \(TakeCircleView.activityDescription(for: currentTake))")
            .accessibilityHint("Double-tap to choose activity types.")
            // Long-press isn't VoiceOver-reachable, so expose discard as a named
            // action (mirrors the timeline Obie long-press). Only when there's
            // content to discard.
            .accessibilityActions {
                if draftHasContent {
                    Button("Discard Take") { discardAndDismiss() }
                }
            }

            Text("Tap the Iris to shape your Take · Long-press to discard")
                .font(CatchlightFont.ui(.medium, size: 11, relativeTo: .caption).italic())   // .tm
                .foregroundStyle(Color.ckTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// The live (unsaved) Take, so the footer Iris and the Focus ring reflect
    /// what's on screen.
    private var currentTake: Take { draft }

    /// Whether the draft has anything worth keeping — the same blank test
    /// `saveAndDismiss` uses, inverted. Drives the discard × affordance (the ×
    /// only appears when there is content to abandon).
    private var draftHasContent: Bool {
        let blank = draft.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.isTask && draft.timeReminder == nil && !draft.isObie
            && draft.attachments.isEmpty && draft.locationReminder == nil
        return !blank
    }

    // MARK: - Save / dismiss

    private func saveAndDismiss() {
        focusedBlockID = nil
        // Task 6.20: the gate lives at the commit, not the navigation. Any path
        // that reaches the editor funnels through here; lapsed users have their
        // edit redirected to the paywall without losing what they typed (the
        // close still happens so the dim layer + keyboard release — the paywall
        // overlays cleanly).
        guard app.ensureEntitled() else {
            ui.closeEditor()
            return
        }
        var t = draft
        // Drop the seeded / return-exited empty prose rows so they don't linger
        // in the saved content, preview, or export.
        t.removeEmptyTextBlocks()
        // Blank-Take discard (2026-06-10): a NEW Take dismissed with no content
        // and no shaping leaves nothing behind. Scope deliberately narrow:
        //   • every content field empty (a check item — even empty — counts as
        //     content, so `!isTask` guards it), AND
        //   • the Take must not already exist in the store with content —
        //     deliberately erasing an old note keeps an "Untitled Take" row the
        //     user can delete explicitly, rather than silently destroying it.
        let isBlank = t.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !t.isTask && t.timeReminder == nil && !t.isObie
            && t.attachments.isEmpty && t.locationReminder == nil
        let storedCopy = try? vm.store.take(id: t.id)
        let storedHadContent = (storedCopy?.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        if isBlank && !storedHadContent {
            vm.discardIfPresent(t)
        } else {
            vm.save(t)
        }
        ui.closeEditor()
    }

    /// Intentional discard (long-press the footer Iris — UX §19). Throws the draft
    /// away WITHOUT saving: deletes it from the store if it was already saved
    /// (editing an existing Take), or simply closes for a never-saved new Take —
    /// `discardIfPresent` no-ops when the id isn't in the store. No confirm: the
    /// long-press itself is the deliberate gesture (the spec's accidental-discard
    /// guard). Empty Takes never reach here via the × (it's hidden), but a stray
    /// long-press on one just closes, same as a tap outside.
    private func discardAndDismiss() {
        focusedBlockID = nil
        vm.discardIfPresent(draft)
        ui.closeEditor()
    }
}

#Preview("Edit — Night") {
    let vm = DailiesViewModel(store: InMemoryTakeStore())
    return TakeEditView(take: Take(blocks: [.textLine("A thought half-formed,\nstill worth keeping."),
                                            .checkItem("act on it"),
                                            .checkItem("done already", isComplete: true)]))
        .environment(vm)
        .environment(UIState())
        .background(Color.ckBackground)
        .preferredColorScheme(.dark)
}

#Preview("Edit — Daylight") {
    let vm = DailiesViewModel(store: InMemoryTakeStore())
    return TakeEditView(take: Take(blocks: []))
        .environment(vm)
        .environment(UIState())
        .background(Color.ckBackground)
        .preferredColorScheme(.light)
}
