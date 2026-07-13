#if DEBUG
import SwiftUI
import CatchlightCore

/// DEBUG-only test bed for the UIKit editor rewrite (Pillar 1, `feature/uikit-editor`).
/// Presents the new `BlockEditor` in isolation with a sample Take so caret-follow
/// can be validated on device WITHOUT touching the live edit-in-place path — the
/// owner keeps dogfooding the real editor while this is proven. Reached from
/// Settings → Debug. Never ships (whole file is `#if DEBUG`). Retire once the
/// editor is wired into the real hosts (Milestone 5).
struct BlockEditorHarness: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Take(blocks: [
        .textLine("M2 test — a note line, then checklist items below."),
        .checkItem("Tap the box to toggle done"),
        .checkItem("Return adds an item; empty Return exits to text"),
        .checkItem("Backspace on an empty item merges up", isComplete: true)
    ])
    @State private var focused: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("UIKit Editor — M4")
                    .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .headline))
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
            Divider()
            BlockEditor(draft: $draft, focusedBlockID: $focused,
                        onDiscard: { dismiss() }, diagnostics: true)
                .padding(.horizontal, 20)
                // Opt out of SwiftUI's automatic keyboard avoidance — the editor's
                // own UIKit scroll view reserves the keyboard space, and letting
                // SwiftUI ALSO push up double-avoids and pins the caret too high.
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .background(Color.ckBackground.ignoresSafeArea())
        .onAppear { focused = draft.blocks.first?.id }
    }
}
#endif
