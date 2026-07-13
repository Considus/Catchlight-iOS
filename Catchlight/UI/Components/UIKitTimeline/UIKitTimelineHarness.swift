#if DEBUG
import SwiftUI
import CatchlightCore

/// DEBUG-only test bed for the Pillar 2 UIKit timeline (`feature/uikit-timeline`).
/// Presents the recycling `UICollectionView` with the owner's REAL Takes (from
/// `app.dailiesVM`) so scrolling, recycling, density, order, the Iris, the wire, month
/// sections, and the pinned Obie can be validated on device WITHOUT touching the live
/// Dailies timeline. Reached from Settings › Debug. Never ships.
///
/// P2-M2 (final): real data + Iris + wire (occluder + dots) + month section headers +
/// pinned Obie. Gestures + edit-in-place are later milestones.
struct UIKitTimelineHarness: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app

    @AppStorage(SettingsViewModel.TakeSpacing.defaultsKey)
    private var spacingRaw = SettingsViewModel.TakeSpacing.default.rawValue
    @AppStorage(SettingsViewModel.TakeSort.defaultsKey)
    private var sortRaw = SettingsViewModel.TakeSort.default.rawValue
    private var spacing: SettingsViewModel.TakeSpacing { .init(rawValue: spacingRaw) ?? .default }
    private var sort: SettingsViewModel.TakeSort { .init(rawValue: sortRaw) ?? .default }

    private static let keyFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f
    }()
    private static let titleFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "LLLL yyyy"; return f
    }()

    private var spineX: CGFloat {
        CatchlightLayout.spineX(containerWidth: UIScreen.main.bounds.width)
    }

    /// Real Takes (Obie excluded by the VM) in the chosen Order — `vm.takes` is
    /// newest-first, so oldest-first reverses (matching `DailiesView.orderedTakes`).
    private var orderedTakes: [Take] {
        let takes = app.dailiesVM.takes
        return sort == .oldestFirst ? Array(takes.reversed()) : takes
    }

    /// Month buckets in first-seen order (matching `DailiesView.monthGroups`).
    private var groups: [TimelineMonthGroup] {
        var order: [String] = []
        var byKey: [String: [Take]] = [:]
        for take in orderedTakes {
            let key = Self.keyFmt.string(from: take.createdAt)
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(take)
        }
        return order.map { key in
            let takes = byKey[key] ?? []
            let title = takes.first.map { Self.titleFmt.string(from: $0.createdAt) } ?? key
            return TimelineMonthGroup(id: key, title: title, takes: takes)
        }
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
                // Gutter wire — screen-fixed at the spine, behind everything, carrying the
                // wire through the gaps. Solid + dotted (screen-Y phase, aligning with the
                // per-cell over-Iris dots).
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

                VStack(spacing: 0) {
                    // Pinned Obie above the scrolling months (the VM excludes it from the list).
                    if let obie = app.dailiesVM.obie {
                        TimelineReadCell(take: obie, spineX: spineX, cardGap: spacing.gap)
                    }
                    UIKitTimeline(groups: groups, spineX: spineX, cardGap: spacing.gap)
                }
            }
        }
        .background(Color.ckBackground.ignoresSafeArea())
    }
}
#endif
