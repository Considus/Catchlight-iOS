//
//  BackspaceTextView.swift
//  Catchlight (iOS app target)
//
//  Rescued from `BlockTextEditor.swift` at M7 (2026-07-16). It was declared alongside the
//  RETIRED SwiftUI block editor, but it belongs to the LIVE UIKit one: `BlockEditorViewController`
//  builds every row from it, and its empty-backspace hook is what merges a row into the one above.
//  Deleting its old file took it with them and broke the new editor — hence this move.
//

import UIKit

/// UITextView that reports a Backspace pressed while empty — the signal the
/// editor uses to exit a check item / merge with the block above. UIKit gives
/// no delegate callback for "delete on empty", so we override `deleteBackward`.
final class BackspaceTextView: UITextView {
    var onBackspaceEmpty: (() -> Void)?

    override func deleteBackward() {
        if text.isEmpty {
            onBackspaceEmpty?()
            return
        }
        super.deleteBackward()
    }
}
