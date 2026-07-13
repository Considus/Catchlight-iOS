#if DEBUG
import SwiftUI
import CatchlightCore

/// DEBUG-only test bed for the Pillar 2 UIKit timeline (`feature/uikit-timeline`).
/// Presents the recycling `UICollectionView` with a spread of sample Takes so scrolling,
/// self-sizing heights, and cell recycling can be validated on device WITHOUT touching
/// the live Dailies timeline. Reached from Settings › Debug. Never ships.
///
/// P2-M1: cards only (no Iris/wire/Obie/headers/gestures yet).
struct UIKitTimelineHarness: View {
    @Environment(\.dismiss) private var dismiss

    private let takes: [Take] = (0..<40).map { i in
        switch i % 4 {
        case 0:
            return Take(blocks: [.textLine("Sample note \(i) — a plain thought to fill the row.")])
        case 1:
            return Take(blocks: [.textLine("Task list \(i)"),
                                 .checkItem("first item"),
                                 .checkItem("second item", isComplete: true)])
        case 2:
            return Take(blocks: [.checkItem("Standalone task \(i)")])
        default:
            return Take(blocks: [.textLine("A longer note number \(i) that wraps across a couple of lines so we can watch variable cell heights self-size and recycle correctly as the list scrolls.")])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("UIKit Timeline — P2-M1")
                    .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .headline))
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
            Divider()
            UIKitTimeline(takes: takes)
        }
        .background(Color.ckBackground.ignoresSafeArea())
    }
}
#endif
