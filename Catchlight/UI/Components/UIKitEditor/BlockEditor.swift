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

    func makeUIViewController(context: Context) -> BlockEditorViewController {
        let vc = BlockEditorViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: BlockEditorViewController, context: Context) {
        context.coordinator.parent = self
        vc.apply(blocks: draft.blocks, focusedBlockID: focusedBlockID)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Bridges UIKit edits back to SwiftUI. Milestone 1+: forward text/focus/
    /// Return/Backspace into `parent.draft` via `Take`'s mutators only, and
    /// mirror focus into `parent.focusedBlockID`.
    final class Coordinator: BlockEditorViewControllerDelegate {
        var parent: BlockEditor
        init(_ parent: BlockEditor) { self.parent = parent }
    }
}
