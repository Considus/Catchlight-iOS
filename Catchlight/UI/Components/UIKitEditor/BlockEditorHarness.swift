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
        .textLine("M1 test — press Return to add lines, or type a long paragraph, and watch the caret hold above the keyboard as the Take grows.")
    ])
    @State private var focused: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("UIKit Editor — M1")
                    .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .headline))
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
            Divider()
            BlockEditor(draft: $draft, focusedBlockID: $focused)
                .padding(.horizontal, 20)
        }
        .background(Color.ckBackground.ignoresSafeArea())
        .onAppear { focused = draft.blocks.first?.id }
    }
}
#endif
