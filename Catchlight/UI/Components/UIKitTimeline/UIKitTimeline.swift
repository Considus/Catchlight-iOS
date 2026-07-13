import SwiftUI
import UIKit
import CatchlightCore

/// Pillar 2 (`feature/uikit-timeline`): the recycling `UICollectionView` timeline that
/// replaces the eager SwiftUI `ScrollView`+`VStack`. Recycling returns lazy-load WITH
/// exact geometry (self-sizing cells), which is what retires the eager-VStack compromise
/// and — once the editor is wired in — the whole caret-pin subsystem. See
/// `03_Engineering/UIKit_Pillar2_Timeline_Design_v1.0.md`.
///
/// STATUS: P2-M1 — read-only skeleton. One section, self-sizing card cells, scroll +
/// recycle. Month sections/headers, the pinned Obie, the spine/Iris/wire, gestures, and
/// edit-in-place arrive in later milestones.
struct UIKitTimeline: UIViewControllerRepresentable {
    var takes: [Take]
    /// The spine x (dock "+" column) — where the card's leading inset is measured from.
    var spineX: CGFloat = CatchlightLayout.spineX(containerWidth: UIScreen.main.bounds.width)
    /// The card-to-card gap from the View/density setting (Compact/Standard/Comfort).
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
        vc.apply(takes: takes)
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

final class UIKitTimelineViewController: UIViewController {
    var spineX: CGFloat = 0
    var cardGap: CGFloat = SettingsViewModel.TakeSpacing.default.gap

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, UUID>!
    private var takesByID: [UUID: Take] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.showsSeparators = false
        config.backgroundColor = .clear
        let layout = UICollectionViewCompositionalLayout.list(using: config)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.keyboardDismissMode = .interactive
        view.addSubview(collectionView)

        // Self-sizing cell hosting the SwiftUI card — exact heights, recycled.
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, UUID> {
            [weak self] cell, _, id in
            guard let self, let take = self.takesByID[id] else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                TimelineReadCell(take: take, spineX: self.spineX, cardGap: self.cardGap)
            }
            .margins(.all, 0)
            cell.backgroundConfiguration = .clear()
        }
        dataSource = UICollectionViewDiffableDataSource<Int, UUID>(collectionView: collectionView) {
            cv, indexPath, id in
            cv.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }
    }

    /// M1: a single section of every Take. Month sections come in M2.
    func apply(takes: [Take]) {
        takesByID = Dictionary(takes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
        snapshot.appendSections([0])
        snapshot.appendItems(takes.map(\.id), toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
        // Reconfigure so a live setting change (spineX / cardGap) refreshes cells even
        // when the item ids are unchanged.
        var reconfigured = dataSource.snapshot()
        reconfigured.reconfigureItems(reconfigured.itemIdentifiers)
        dataSource.apply(reconfigured, animatingDifferences: false)
    }
}
