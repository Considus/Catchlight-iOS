//
//  DeleteConfirmation.swift
//  Catchlight (iOS app target) — confirm before deleting (owner 2026-08-16)
//
//  A delete is a hard store delete: no trash, no undo, nothing to restore from. The
//  owner lost a Take to a mis-swipe, so deleting can now ask first — a plain iOS alert,
//  governed by Settings → Security → "Confirm before deleting" (default ON).
//
//  It lives here, as one modifier, because a Take can be deleted from FIVE places across
//  TWO screens: the timeline's swipe and its long-press menu, the pinned Obie's own row,
//  the editing row's menu, and the Storyboard's long-press menu — which reaches the store
//  directly and never touches DailiesView at all. Copies of a rule on those two screens
//  have drifted apart twice already (the `!isObie` term, and the emptied-Take rule), each
//  time producing a bug on exactly one of them. One modifier is the cure: every surface
//  asks the same question, in the same words, with the same buttons.
//
//  NOT used for a repeating reminder. That already asks "this occurrence or the series?",
//  which is a confirmation with more in it than this one — asking twice would be noise.
//

import SwiftUI
import CatchlightCore

extension View {
    /// Ask before deleting `pending`, then hand it to `onConfirm`.
    ///
    /// Set `pending` to the doomed Take to raise the alert; it clears itself on either
    /// button and on a system dismissal. `onConfirm` runs ONLY on Delete, so a surface can
    /// route it straight to its existing delete path with no other bookkeeping.
    ///
    /// The caller decides WHETHER to ask (read the setting, check for a repeating
    /// reminder) — this modifier owns only the asking.
    func deleteConfirmation(pending: Binding<Take?>,
                            onConfirm: @escaping (Take) -> Void) -> some View {
        alert("Delete this Take?",
              isPresented: Binding(get: { pending.wrappedValue != nil },
                                   set: { if !$0 { pending.wrappedValue = nil } }),
              presenting: pending.wrappedValue) { doomed in
            // Destructive first, cancel second — the iOS order the app's other
            // destructive prompts already use.
            Button("Delete", role: .destructive) {
                onConfirm(doomed)
                pending.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) { pending.wrappedValue = nil }
        } message: { _ in
            Text("This cannot be undone.")
        }
    }
}
