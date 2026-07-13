import SwiftUI
import UIKit
import CatchlightCore

/// Pillar 2 (`feature/uikit-timeline`): the recycling `UICollectionView` timeline that
/// replaces the eager SwiftUI `ScrollView`+`VStack`. Sections = month buckets, items =
/// Takes. Recycling returns lazy-load WITH exact geometry (self-sizing cells). See
/// `03_Engineering/UIKit_Pillar2_Timeline_Design_v1.0.md`.
///
/// STATUS: P2-M2 — read-only. Real Takes, month sections + headers, Iris + wire. The
/// pinned Obie is rendered by the host above this view. Gestures and edit-in-place are
/// later milestones; the tight-S wire redesign is the finish.

/// A month group: section id (yyyy-MM), display title (LLLL yyyy), and its Takes.
struct TimelineMonthGroup: Identifiable {
    let id: String
    let title: String
    let takes: [Take]
}

struct UIKitTimeline: UIViewControllerRepresentable {
    var groups: [TimelineMonthGroup]
    var spineX: CGFloat = CatchlightLayout.spineX(containerWidth: UIScreen.main.bounds.width)
    var cardGap: CGFloat = SettingsViewModel.TakeSpacing.default.gap

    func makeUIViewController(context: Context) -> UIKitTimelineViewController {
        let vc = UIKitTimelineViewController()
        vc.spineX = spineX
        vc.cardGap = cardGap
        return vc
    }

    func updateUIViewController(_ vc: UIKitTimelineViewController, context: Context) {
        vc.spineX = spineX
        vc.cardGap = cardGap
        vc.apply(groups: groups)
    }
}

/// One read-only timeline row — the same layering as `TakeRowView` (card < occluder <
/// Iris < wire segment < dots), so the wire threads the Iris identically. Offsets are
/// `cardSpineInset`-relative (the ZStack origin is the card's top-left, after the leading
/// pad). The gutter wire between rows is the screen-fixed line drawn behind the collection.
struct TimelineReadCell: View {
    let take: Take
    let spineX: CGFloat
    let cardGap: CGFloat

    private let inset = CatchlightLayout.cardSpineInset
    private let d = CatchlightLayout.circleDiameter
    private let w = CatchlightLayout.spineWidth
    private var occW: CGFloat { CatchlightLayout.spineWidth + CatchlightLayout.spineTrackOffset * 2 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TakeCardSurface(take: take, linksInteractive: false)                       // card
            Rectangle().fill(Color.ckBackground)                                       // occluder
                .frame(width: occW, height: d / 2)
                .offset(x: inset - occW / 2, y: -d / 2)
                .allowsHitTesting(false)
            TakeCircleView(take: take)                                                 // Iris
                .frame(width: d, height: d)
                .offset(x: inset - d / 2, y: -d / 2)
            SpineLine().stroke(Color.ckSpineWire, lineWidth: w)                        // wire over Iris top
                .frame(width: w, height: d / 2)
                .offset(x: inset - w / 2, y: -d / 2)
                .allowsHitTesting(false)
            GeometryReader { geo in                                                    // dots over Iris top
                SpineLine().stroke(SpineDots.color,
                                   style: SpineDots.style(phase: geo.frame(in: .global).minY))
            }
            .frame(width: w, height: d / 2)
            .offset(x: inset - w / 2, y: -d / 2)
            .allowsHitTesting(false)
        }
        .padding(.leading, spineX - inset)
        .padding(.trailing, 20)
        .padding(.top, cardGap)
    }
}

/// A month divider label, matching the current timeline's `group.month` header (kerned
/// caps at the card-text column).
struct TimelineSectionHeader: View {
    let title: String
    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .body))
                .kerning(0.5)
                .foregroundStyle(Color.ckTextSecondary)
            Spacer()
        }
        .padding(.leading, CatchlightLayout.cardTextLeadingPad)
        .padding(.vertical, 6)
    }
}

final class UIKitTimelineViewController: UIViewController {
    var spineX: CGFloat = 0
    var cardGap: CGFloat = SettingsViewModel.TakeSpacing.default.gap

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<String, UUID>!
    private var takesByID: [UUID: Take] = [:]
    private var groupTitles: [String: String] = [:]
    private var sectionOrder: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.showsSeparators = false
        config.backgroundColor = .clear
        config.headerMode = .supplementary
        let layout = UICollectionViewCompositionalLayout.list(using: config)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.keyboardDismissMode = .interactive
        view.addSubview(collectionView)

        let cellReg = UICollectionView.CellRegistration<UICollectionViewListCell, UUID> {
            [weak self] cell, _, id in
            guard let self, let take = self.takesByID[id] else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                TimelineReadCell(take: take, spineX: self.spineX, cardGap: self.cardGap)
            }
            .margins(.all, 0)
            cell.backgroundConfiguration = .clear()
        }

        let headerReg = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader) { [weak self] header, _, indexPath in
            guard let self else { return }
            // Suppress the first section's month label (the DAILIES heading is its
            // context in the real view), matching the current timeline.
            if indexPath.section == 0 {
                header.contentConfiguration = UIHostingConfiguration { Color.clear.frame(height: 0) }
                    .margins(.all, 0)
            } else {
                let title = self.groupTitles[self.sectionOrder[safe: indexPath.section] ?? ""] ?? ""
                header.contentConfiguration = UIHostingConfiguration { TimelineSectionHeader(title: title) }
                    .margins(.all, 0)
            }
            header.backgroundConfiguration = .clear()
        }

        dataSource = UICollectionViewDiffableDataSource<String, UUID>(collectionView: collectionView) {
            cv, indexPath, id in
            cv.dequeueConfiguredReusableCell(using: cellReg, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath)
        }
    }

    func apply(groups: [TimelineMonthGroup]) {
        takesByID = Dictionary(groups.flatMap(\.takes).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        groupTitles = Dictionary(groups.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        sectionOrder = groups.map(\.id)

        var snapshot = NSDiffableDataSourceSnapshot<String, UUID>()
        snapshot.appendSections(sectionOrder)
        for group in groups { snapshot.appendItems(group.takes.map(\.id), toSection: group.id) }
        dataSource.apply(snapshot, animatingDifferences: false)

        // Reconfigure so a live setting change (spineX / cardGap) refreshes cells.
        var reconfigured = dataSource.snapshot()
        reconfigured.reconfigureItems(reconfigured.itemIdentifiers)
        dataSource.apply(reconfigured, animatingDifferences: false)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
