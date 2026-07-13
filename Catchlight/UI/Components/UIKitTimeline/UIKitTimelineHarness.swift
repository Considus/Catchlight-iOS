#if DEBUG
import SwiftUI
import CatchlightCore

/// DEBUG-only test bed for the Pillar 2 UIKit timeline (`feature/uikit-timeline`).
/// Presents the recycling `UICollectionView` with the owner's REAL Takes (read from
/// `app.dailiesVM`) so scrolling, self-sizing, recycling, density, order, the Iris, and
/// the wire can be validated on device WITHOUT touching the live Dailies timeline.
/// Reached from Settings › Debug. Never ships.
///
/// P2-M2 (step 1): real data + Iris + a simple screen-fixed wire. The occluder + dotted
/// wire, month section headers, and the pinned Obie come next.
struct UIKitTimelineHarness: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app

    @AppStorage(SettingsViewModel.TakeSpacing.defaultsKey)
    private var spacingRaw = SettingsViewModel.TakeSpacing.default.rawValue
    @AppStorage(SettingsViewModel.TakeSort.defaultsKey)
    private var sortRaw = SettingsViewModel.TakeSort.default.rawValue
    private var spacing: SettingsViewModel.TakeSpacing { .init(rawValue: spacingRaw) ?? .default }
    private var sort: SettingsViewModel.TakeSort { .init(rawValue: sortRaw) ?? .default }

    /// The real Takes (Obie already excluded by the VM), in the chosen Order. `vm.takes`
    /// is newest-first, so oldest-first reverses — matching `DailiesView.orderedTakes`.
    private var orderedTakes: [Take] {
        let takes = app.dailiesVM.takes
        return sort == .oldestFirst ? Array(takes.reversed()) : takes
    }

    private var spineX: CGFloat {
        CatchlightLayout.spineX(containerWidth: UIScreen.main.bounds.width)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("UIKit Timeline — P2-M2")
                    .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .headline))
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
            Divider()
            ZStack(alignment: .topLeading) {
                // The gutter wire — screen-fixed at the spine column, behind the cells,
                // carrying the wire through the gaps between cards. Solid + dotted (three
                // tracks via SpineLine); the dot phase anchors to screen-Y so it aligns
                // with the per-cell over-Iris dots. The tight-S redesign lands last.
                SpineLine().stroke(Color.ckSpineWire, lineWidth: CatchlightLayout.spineWidth)
                    .frame(width: CatchlightLayout.spineWidth)
                    .frame(maxHeight: .infinity)
                    .offset(x: spineX - CatchlightLayout.spineWidth / 2)
                GeometryReader { geo in
                    SpineLine().stroke(SpineDots.color,
                                       style: SpineDots.style(phase: geo.frame(in: .global).minY))
                }
                .frame(width: CatchlightLayout.spineWidth)
                .frame(maxHeight: .infinity)
                .offset(x: spineX - CatchlightLayout.spineWidth / 2)

                UIKitTimeline(takes: orderedTakes, spineX: spineX, cardGap: spacing.gap)
            }
        }
        .background(Color.ckBackground.ignoresSafeArea())
    }
}
#endif
