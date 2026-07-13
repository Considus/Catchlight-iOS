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

    func makeUIViewController(context: Context) -> UIKitTimelineViewController {
        let vc = UIKitTimelineViewController()
        vc.spineX = spineX
        return vc
    }

    func updateUIViewController(_ vc: UIKitTimelineViewController, context: Context) {
        vc.spineX = spineX
        vc.apply(takes: takes)
    }
}

/// One read-only timeline row (M1: the card only, at the spine-relative leading inset).
/// The Iris + occluder land in M2; the wire becomes a layout decoration.
struct TimelineReadCell: View {
    let take: Take
    let spineX: CGFloat
    var body: some View {
        TakeCardSurface(take: take, linksInteractive: false)
            .padding(.leading, spineX - CatchlightLayout.cardSpineInset)
            .padding(.trailing, 20)
            .padding(.vertical, 6)
    }
}

final class UIKitTimelineViewController: UIViewController {
    var spineX: CGFloat = 0

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
                TimelineReadCell(take: take, spineX: self.spineX)
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
    }
}
