import SwiftUI
import UIKit
import CatchlightCore

/// Pillar 1 (`feature/uikit-editor`, 2026-07-13): the self-scrolling UIKit
/// replacement for the SwiftUI block-stack editor (`InlineTakeEditCard` +
/// per-block `BlockTextEditor`). ONE scroll-enabled list of block-rows — the
/// LIST scrolls, so caret-follow is NATIVE (`scrollRectToVisible`) and the
/// hand-rolled caret pin in `DailiesView` can be retired. This is the fix for
/// the caret-below-keyboard bug that returned four times.
///
/// Designed as a drop-in for `InlineTakeEditCard` so all three hosts
/// (`DailiesView`, `StoryboardView`, `LockedCaptureView`) keep the same seam.
/// See `03_Engineering/UIKit_Pillar1_Editor_Design_v1.0.md`.
///
/// STATUS: skeleton only — the seam is declared; Milestone 1 (text rows +
/// native caret-follow) is not yet implemented.
struct BlockEditor: UIViewControllerRepresentable {
    /// Single source of truth. Mutate ONLY through `Take`'s block mutators so
    /// the derived flags (`isTask`/`isComplete`/`checkItems`/`isMarkedDone`)
    /// never drift.
    @Binding var draft: Take
    /// Kept even though focus is now UIKit-native: hosts drive/observe it
    /// (Angle/reminder excursions park & restore it; `nil` = release keyboard).
    @Binding var focusedBlockID: UUID?

    var onOpenAngle: (() -> Void)? = nil
    var onEditReminder: (() -> Void)? = nil
    /// The keyboard × discards (revert); save is the host's tap-away.
    var onDiscard: (() -> Void)? = nil
    /// Retained for the seam only. A self-scrolling editor should leave this
    /// unset so `DailiesView` skips the (to-be-deleted) caret pin.
    var onCaretMoved: ((CGRect) -> Void)? = nil

    #if DEBUG
    /// The test harness turns on an on-device readout of the scroll maths.
    var diagnostics = false
    #endif

    func makeUIViewController(context: Context) -> BlockEditorViewController {
        let vc = BlockEditorViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: BlockEditorViewController, context: Context) {
        context.coordinator.parent = self
        #if DEBUG
        vc.showsDiagnostics = diagnostics
        #endif
        vc.apply(blocks: draft.blocks, focusedBlockID: focusedBlockID)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Bridges UIKit edits back to SwiftUI. Milestone 1: text + focus. Mutates
    /// `parent.draft` only through `Take`'s mutators so derived flags stay
    /// consistent. Return/Backspace/check-toggle arrive in M2.
    final class Coordinator: BlockEditorViewControllerDelegate {
        var parent: BlockEditor
        init(_ parent: BlockEditor) { self.parent = parent }

        func blockEditor(_ vc: BlockEditorViewController, didChangeText text: String, forBlock id: UUID) {
            parent.draft.updateText(text, blockID: id)
        }

        func blockEditor(_ vc: BlockEditorViewController, didFocusBlock id: UUID?) {
            if parent.focusedBlockID != id { parent.focusedBlockID = id }
        }

        // Return in a check row — mirrors the current editor's `handleReturn`.
        func blockEditorReturnInCheckRow(_ vc: BlockEditorViewController, blockID id: UUID) {
            let isEmpty = (parent.draft.blocks.first { $0.id == id }?.text ?? "").isEmpty
            if isEmpty {
                parent.draft.convertCheckToText(blockID: id)   // empty item → exit to prose
                parent.focusedBlockID = id
            } else {
                parent.focusedBlockID = parent.draft.insertCheckItem(after: id)
            }
        }

        // Backspace on an empty row — mirrors the current editor's `handleBackspaceEmpty`.
        func blockEditorBackspaceOnEmpty(_ vc: BlockEditorViewController, blockID id: UUID) {
            let isCheck = parent.draft.blocks.first { $0.id == id }?.isCheck ?? false
            if let previous = parent.draft.blockID(before: id) {
                parent.draft.removeBlock(blockID: id)
                if parent.draft.blocks.isEmpty {
                    let t = TextBlock(text: "")
                    parent.draft.blocks = [.text(t)]
                    parent.focusedBlockID = t.id
                } else {
                    parent.focusedBlockID = previous
                }
            } else if isCheck {
                parent.draft.convertCheckToText(blockID: id)   // first item, no prior block
                parent.focusedBlockID = id
            }
        }

        func blockEditorToggleCheck(_ vc: BlockEditorViewController, blockID id: UUID) {
            parent.draft.toggleItemComplete(blockID: id)
        }
    }
}
