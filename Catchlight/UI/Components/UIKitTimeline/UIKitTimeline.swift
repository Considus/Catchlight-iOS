import SwiftUI
import UIKit
import CatchlightCore

/// Pillar 2 (`feature/uikit-timeline`): the recycling `UICollectionView` timeline that
/// replaces the eager SwiftUI `ScrollView`+`VStack`. Recycling returns lazy-load WITH
/// exact geometry (self-sizing cells). See
/// `03_Engineering/UIKit_Pillar2_Timeline_Design_v1.0.md`.
///
/// STATUS: P2-M2 — read-only. Real Takes, month DIVIDER rows (a row in the flow, like the
/// real timeline — centred between Takes, at the text column), Iris + wire. The pinned
/// Obie is rendered by the host above this view. Gestures and edit-in-place are later.

/// A month group: id (yyyy-MM), display title (LLLL yyyy), and its Takes.
struct TimelineMonthGroup: Identifiable {
    let id: String
    let title: String
    let takes: [Take]
}

/// One row in the flow: a month divider or a Take. Single section; the divider is a
/// regular item (not a section header), so it centres between Takes and shares their
/// spacing + text column — matching the current timeline's divider.
enum TimelineRow: Hashable {
    case month(String)   // group id
    case take(UUID)
}

struct UIKitTimeline: UIViewControllerRepresentable {
    var groups: [TimelineMonthGroup]
    var spineX: CGFloat = CatchlightLayout.spineX(containerWidth: UIScreen.main.bounds.width)
    var cardGap: CGFloat = SettingsViewModel.TakeSpacing.default.gap
    /// The month key ("yyyy-MM") currently filtering the timeline, if any — that divider lights
    /// amber with an × and always shows (even as the first group) so the clear affordance survives.
    var activeMonthKey: String? = nil
    /// Tap a month divider → filter to that creation month; tap the lit one again → clear.
    var onToggleMonthFilter: (String) -> Void = { _ in }
    /// Top inset so content clears the pinned heading + Obie zone; bottom for the dock.
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    /// Swipe actions (native), wired to the host's entitlement-gated Take actions.
    var onToggleDone: (Take) -> Void = { _ in }
    var onDelete: (Take) -> Void = { _ in }
    /// Iris tap → open the Focus-ring fan at the given WINDOW-coord centre; long-press
    /// → toggle Obie. Wired to the same `ui`/`vm` the SwiftUI timeline uses.
    var onTapCircle: (Take, CGPoint) -> Void = { _, _ in }
    var onLongPressCircle: (Take) -> Void = { _ in }
    /// Card context-menu actions (resting-row set). Mark-done/Delete reuse the swipe
    /// closures above; these three are the menu-only extras.
    var onSetImportant: (Take) -> Void = { _ in }
    var onMakeObie: (Take) -> Void = { _ in }
    var onExport: (Take) -> Void = { _ in }
    /// Tap a card → begin edit-in-place / commit an open edit (M4.1).
    var onTapText: (Take) -> Void = { _ in }
    /// M4.2 — reports the tapped card's frame in WINDOW coords at tap time, so the host
    /// can anchor the editor overlay in place (same coord pattern as the Focus-ring fan).
    var onEditAnchor: (CGRect) -> Void = { _ in }
    /// M4.6 — while editing, FADE + disable the collection itself (like the old timeline
    /// fades its rows to 0.12), so the cards recede and taps fall THROUGH to the save
    /// catcher behind. This avoids fighting the representable's compositing (the collection
    /// otherwise sits above the SwiftUI veil for hit-testing — tap-between-Takes was dead).
    var isEditing: Bool = false

    func makeUIViewController(context: Context) -> UIKitTimelineViewController {
        let vc = UIKitTimelineViewController()
        vc.spineX = spineX
        vc.cardGap = cardGap
        vc.activeMonthKey = activeMonthKey
        vc.onToggleMonthFilter = onToggleMonthFilter
        vc.topInset = topInset
        vc.bottomInset = bottomInset
        vc.onToggleDone = onToggleDone
        vc.onDelete = onDelete
        vc.onTapCircle = onTapCircle
        vc.onLongPressCircle = onLongPressCircle
        vc.onSetImportant = onSetImportant
        vc.onMakeObie = onMakeObie
        vc.onExport = onExport
        vc.onTapText = onTapText
        vc.onEditAnchor = onEditAnchor
        return vc
    }

    func updateUIViewController(_ vc: UIKitTimelineViewController, context: Context) {
        vc.spineX = spineX
        vc.cardGap = cardGap
        vc.activeMonthKey = activeMonthKey
        vc.onToggleMonthFilter = onToggleMonthFilter
        vc.topInset = topInset
        vc.bottomInset = bottomInset
        vc.onToggleDone = onToggleDone
        vc.onDelete = onDelete
        vc.onTapCircle = onTapCircle
        vc.onLongPressCircle = onLongPressCircle
        vc.onSetImportant = onSetImportant
        vc.onMakeObie = onMakeObie
        vc.onExport = onExport
        vc.onTapText = onTapText
        vc.onEditAnchor = onEditAnchor
        vc.apply(groups: groups)
        vc.updateEditing(isEditing)
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
    /// Iris tap → the CGPoint is the Iris centre in WINDOW (global) coords, so the
    /// host can bloom the Focus-ring fan in place (matches `RootView`'s full-screen
    /// `ignoresSafeArea` overlay space). Long-press → toggle Obie. Both reuse the
    /// existing `TapAndLongPressRecognizer` from `TakeRowView` (built to survive the
    /// move to a UIKit-hosted cell).
    var onTapCircle: (Take, CGPoint) -> Void = { _, _ in }
    var onLongPressCircle: (Take) -> Void = { _ in }
    /// Card context-menu actions (mirrors `TakeRowView.rowMenuItems`, resting variant).
    /// Mark-done / Delete reuse the swipe closures; the menu-delete is thus recurring-
    /// aware too. Attached to the CARD only — the Iris is a sibling, so its long-press
    /// (Obie) still wins, matching the SwiftUI row's deliberate split.
    var onToggleDone: (Take) -> Void = { _ in }
    var onDelete: (Take) -> Void = { _ in }
    var onSetImportant: (Take) -> Void = { _ in }
    var onMakeObie: (Take) -> Void = { _ in }
    var onExport: (Take) -> Void = { _ in }
    /// Tap the card → begin edit-in-place (M4.1), or commit an open edit of another Take.
    var onTapText: (Take) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    private let inset = CatchlightLayout.cardSpineInset
    private let d = CatchlightLayout.circleDiameter
    private let w = CatchlightLayout.spineWidth
    private var occW: CGFloat { CatchlightLayout.spineWidth + CatchlightLayout.spineTrackOffset * 2 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TakeCardSurface(take: take, linksInteractive: false)                       // card
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture { onTapText(take) }
                .contextMenu { menuItems }
            Rectangle().fill(Color.ckBackground)                                       // occluder
                .frame(width: occW, height: d / 2)
                .offset(x: inset - occW / 2, y: -d / 2)
                .allowsHitTesting(false)
            TakeCircleView(take: take)                                                 // Iris
                .frame(width: d, height: d)
                // Lift the Iris off the background (owner 2026-07-13) — raised but still
                // attached to the card. Stronger than the card's default shadow because
                // the Iris is smaller + partly hollow, so it casts less. `caretBottomGap`-
                // style single tunable: bump/soften via the opacity/radius here.
                .shadow(color: scheme == .dark ? .clear : Color.ckInk.opacity(0.16),
                        radius: 5, y: 2)
                .contentShape(Rectangle())
                // Tap → Focus-ring fan, long-press (0.45s, .began) → toggle Obie. Same
                // recognizer the SwiftUI row uses; `convert(_:to: nil)` yields the Iris
                // centre in window coords. The overloccluding wire/dots are hit-testing-
                // off, so touches reach this overlay.
                .overlay(
                    TapAndLongPressRecognizer(
                        minimumDuration: 0.45,
                        onTap: { onTapCircle(take, $0) },
                        onLongPress: { onLongPressCircle(take) }
                    )
                )
                .offset(x: inset - d / 2, y: -d / 2)
            SpineLine().stroke(Color.ckSpineWire, lineWidth: w)                        // wire over Iris top
                .frame(width: w, height: d / 2)
                .offset(x: inset - w / 2, y: -d / 2)
                .allowsHitTesting(false)
            // Dots over the Iris top. The phase is FIXED — it must NOT read the cell's scroll
            // position. A `GeometryReader { geo.frame(in: .global).minY }` here (to phase-match the
            // screen-fixed gutter dashes) made the cell's content depend on its scroll offset: inside
            // a self-sizing UIHostingConfiguration that re-measures the cell on every scroll tick, so
            // the layout invalidates DURING the visible-cells pass and recurses until UIKit trips its
            // assertion — a hard CRASH plus stuttery scroll (device crash logs 2026-07-16:
            // -[UICollectionView _updateVisibleCellsNow:] 7 deep → _assertionFailure).
            // Trade: the dash rhythm no longer continues the gutter's exactly at each Iris. M6's wire
            // redesign replaces this segment wholesale; if the seam reads badly before then, draw it
            // in a UIKit layer the VC updates on scroll — never in the cell's SwiftUI content.
            SpineLine().stroke(SpineDots.color, style: SpineDots.style(phase: 0))
                .frame(width: w, height: d / 2)
                .offset(x: inset - w / 2, y: -d / 2)
                .allowsHitTesting(false)
        }
        .padding(.leading, spineX - inset)
        .padding(.trailing, 20)
        // SYMMETRIC so the card is centred in the cell — a swipe action fill then centres
        // on the CARD, not the cell (the Iris overhang is render-only `.offset`, so it
        // doesn't grow the layout; the cell must simply not clip).
        .padding(.vertical, cardGap / 2)
    }

    /// The resting-row menu (mirrors `TakeRowView.rowMenuItems`, minus the edit-only
    /// "Discard changes" — the new timeline has no edit-in-place yet, M4).
    @ViewBuilder
    private var menuItems: some View {
        if take.canBeMarkedDone {
            Button {
                onToggleDone(take)
            } label: {
                Label(take.isMarkedDone ? "Mark Not Done" : "Mark Done",
                      systemImage: take.isMarkedDone ? "circle" : "checkmark.circle")
            }
        }
        Button {
            onSetImportant(take)
        } label: {
            if take.isImportant {
                Label { Text("Remove Important") } icon: { MenuGlyph.removeImportant }
            } else {
                Label { Text("Make Important") } icon: { MenuGlyph.makeImportant }
            }
        }
        if !take.isObie {
            Button {
                onMakeObie(take)
            } label: {
                Label { Text("Make Obie") } icon: { MenuGlyph.obie }
            }
        }
        Button {
            onExport(take)
        } label: {
            Label("Export Take", systemImage: "square.and.arrow.up")
        }
        Button(role: .destructive) {
            onDelete(take)
        } label: {
            Label("Delete Take", systemImage: "trash")
        }
    }
}

/// Shared single-open coordination for the custom swipe rows.
@Observable final class TimelineSwipeState {
    var openRowID: UUID?
}

/// A Take row wrapped in the app's own `SwipeActionRow` (the SwiftUI-version swipe: fill
/// tucks under the card, full-swipe commit, resting-open). The WHOLE cell content slides,
/// so the Iris rides with the card (owner 2026-07-13). `contentVerticalInset = cardGap/2`
/// centres the action fill on the card regardless of card height.
struct TimelineSwipeCell: View {
    let take: Take
    let spineX: CGFloat
    let cardGap: CGFloat
    @Bindable var swipeState: TimelineSwipeState
    let onToggleDone: (Take) -> Void
    let onDelete: (Take) -> Void
    var onTapCircle: (Take, CGPoint) -> Void = { _, _ in }
    var onLongPressCircle: (Take) -> Void = { _ in }
    var onSetImportant: (Take) -> Void = { _ in }
    var onMakeObie: (Take) -> Void = { _ in }
    var onExport: (Take) -> Void = { _ in }
    var onTapText: (Take) -> Void = { _ in }

    var body: some View {
        SwipeActionRow(
            id: take.id,
            leading: take.canBeMarkedDone
                ? SwipeAction(title: take.isMarkedDone ? "Not done" : "Done",
                              systemImage: take.isMarkedDone ? "arrow.uturn.left" : "checkmark",
                              tint: .ckEmber, style: .standard,
                              perform: { onToggleDone(take) })
                : nil,
            trailing: SwipeAction(title: "Delete", systemImage: "trash", tint: .ckRuby,
                                  style: take.timeReminder?.repeats == true ? .standard : .destructive,
                                  perform: { onDelete(take) }),
            openRowID: $swipeState.openRowID,
            leadingInset: spineX - CatchlightLayout.cardSpineInset,
            trailingInset: 20,
            contentVerticalInset: cardGap / 2,
            centersActionLabel: true    // centre glyph/label in the revealed button, not hugged to the screen edge
        ) { offset in
            TimelineReadCell(take: take, spineX: spineX, cardGap: cardGap,
                             onTapCircle: onTapCircle, onLongPressCircle: onLongPressCircle,
                             onToggleDone: onToggleDone, onDelete: onDelete,
                             onSetImportant: onSetImportant, onMakeObie: onMakeObie,
                             onExport: onExport, onTapText: onTapText)
                .offset(x: offset)
        }
        // Pin to NATURAL height. `SwipeActionRow`'s action fills are `maxHeight: .infinity`, and a
        // self-sizing `UIHostingConfiguration` proposes an UNBOUNDED height — so the fill stretches
        // and the cell's measured height never settles. The layout then invalidates during the
        // visible-cells pass and re-measures, over and over: stuttery, jumpy scroll that recurses
        // until UIKit trips its assertion (device crash logs 2026-07-16: -[UICollectionView
        // _updateVisibleCellsNow:] 7 deep → _assertionFailure). `DailiesView` hit the same trap
        // hosting the pinned Obie and pins it the same way.
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A month divider row — kerned caps at the card TEXT column, centred in the inter-card
/// gap. Each adjacent card contributes a `cardGap/2` half-gap on its facing edge, so a
/// SYMMETRIC `cardGap/2` here puts equal space (`cardGap`) above and below the label —
/// centred on the y-axis — while keeping the overall card-to-card gap unchanged.
struct TimelineMonthDivider: View {
    let title: String
    let spineX: CGFloat
    let cardGap: CGFloat
    /// This month is the ACTIVE filter — lit amber with an × as the clear affordance.
    var isActive: Bool = false
    /// TAP to filter the timeline to this creation month; tap the lit one again to clear.
    var onTap: () -> Void = {}
    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .body))
                .kerning(0.5)
                .foregroundStyle(isActive ? Color.ckTextObie : Color.ckTextSecondary)
            if isActive {
                Image(systemName: "xmark.circle.fill")
                    .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .caption))
                    .foregroundStyle(Color.ckTextObie)
                    .accessibilityHidden(true)
            }
            Spacer()
        }
        .padding(.leading, spineX - CatchlightLayout.cardSpineInset + CatchlightLayout.cardTextLeadingPad)
        .padding(.trailing, 20)
        .padding(.vertical, cardGap / 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isActive
            ? "\(title), filtering. Double-tap to clear."
            : "\(title). Double-tap to show only Takes created this month.")
    }
}

final class UIKitTimelineViewController: UIViewController {
    var spineX: CGFloat = 0
    var cardGap: CGFloat = SettingsViewModel.TakeSpacing.default.gap
    var activeMonthKey: String?
    var onToggleMonthFilter: (String) -> Void = { _ in }
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    var onToggleDone: (Take) -> Void = { _ in }
    var onDelete: (Take) -> Void = { _ in }
    var onTapCircle: (Take, CGPoint) -> Void = { _, _ in }
    var onLongPressCircle: (Take) -> Void = { _ in }
    var onSetImportant: (Take) -> Void = { _ in }
    var onMakeObie: (Take) -> Void = { _ in }
    var onExport: (Take) -> Void = { _ in }
    var onTapText: (Take) -> Void = { _ in }
    var onEditAnchor: (CGRect) -> Void = { _ in }

    private let swipeState = TimelineSwipeState()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, TimelineRow>!
    private var takesByID: [UUID: Take] = [:]
    private var previousTakes: [UUID: Take] = [:]   // reconfigure only what changed
    private var lastItems: [TimelineRow] = []        // skip re-applying an unchanged snapshot
    private var lastSpineX: CGFloat = -1             // density/spine change → reconfigure all
    private var lastCardGap: CGFloat = -1
    private var lastActiveMonthKey: String??        // month-filter change → restyle the dividers
    private var groupTitles: [String: String] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.showsSeparators = false
        config.backgroundColor = .clear
        // Swipe is the app's own SwipeActionRow, hosted in the cell (below) — not the
        // native provider — so the fill/buttons match the SwiftUI version and centre on
        // the card. Native `.trailingSwipeActionsConfigurationProvider` is intentionally
        // NOT set.
        let layout = UICollectionViewCompositionalLayout.list(using: config)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // BISECT 2026-07-16: `.never` here (to stop iOS double-counting the top safe area — see
        // `newTimelineTopInset`) correlates EXACTLY with the onset of a fatal collection-layout
        // recursion (`_updateVisibleCellsNow` 7 deep → _assertionFailure) plus stuttery scroll:
        // no such crash before it, three after. Reverted to the default while we confirm the cause;
        // the top Take goes back to sitting too low until the inset is fixed another way.
        // collectionView.contentInsetAdjustmentBehavior = .never
        // .none (not .interactive): with the new-Take overlay's keyboard up and this
        // collection behind it, interactive tracking contributed to keyboard re-placement
        // thrash (caps-flash, attempt 1). Nothing here needs scroll-to-dismiss.
        collectionView.keyboardDismissMode = .none
        view.addSubview(collectionView)

        let cellReg = UICollectionView.CellRegistration<UICollectionViewListCell, TimelineRow> {
            [weak self] cell, _, row in
            guard let self else { return }
            // Don't clip: the Iris straddles above the card (render-only overhang).
            cell.clipsToBounds = false
            cell.contentView.clipsToBounds = false
            switch row {
            case .take(let id):
                guard let take = self.takesByID[id] else { return }
                cell.contentConfiguration = UIHostingConfiguration {
                    TimelineSwipeCell(take: take, spineX: self.spineX, cardGap: self.cardGap,
                                      swipeState: self.swipeState,
                                      onToggleDone: { self.onToggleDone($0) },
                                      onDelete: { self.onDelete($0) },
                                      onTapCircle: { self.onTapCircle($0, $1) },
                                      onLongPressCircle: { self.onLongPressCircle($0) },
                                      onSetImportant: { self.onSetImportant($0) },
                                      onMakeObie: { self.onMakeObie($0) },
                                      onExport: { self.onExport($0) },
                                      onTapText: { [weak self] tapped in
                                          guard let self else { return }
                                          // Report the tapped card's on-screen frame FIRST
                                          // (before the edit begins) so the host anchors the
                                          // editor in place, then begin the edit.
                                          self.onEditAnchor(self.cardFrameInWindow(for: tapped.id))
                                          self.onTapText(tapped)
                                      })
                }
                .margins(.all, 0)
            case .month(let key):
                cell.contentConfiguration = UIHostingConfiguration {
                    TimelineMonthDivider(title: self.groupTitles[key] ?? "",
                                         spineX: self.spineX, cardGap: self.cardGap,
                                         isActive: self.activeMonthKey == key,
                                         onTap: { self.onToggleMonthFilter(key) })
                }
                .margins(.all, 0)
            }
            cell.backgroundConfiguration = .clear()
        }
        dataSource = UICollectionViewDiffableDataSource<Int, TimelineRow>(collectionView: collectionView) {
            cv, indexPath, row in
            cv.dequeueConfiguredReusableCell(using: cellReg, for: indexPath, item: row)
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        applyContentInsets()   // the compensation below depends on the safe area — re-derive it
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Re-derive here too: on the FIRST layout `safeAreaInsets` is still zero, so the
        // compensation subtracts nothing and the top Take renders low — then pops up a beat later
        // when some unrelated update happens to call `apply` (owner 2026-07-15). Deriving it on
        // every layout lands it on the first pass instead. `applyContentInsets` only writes on a
        // real change, so this can't ping-pong.
        applyContentInsets()
    }

    /// The default `contentInsetAdjustmentBehavior` ADDS `safeAreaInsets` to `contentInset`, but
    /// `topInset` already includes `deviceTopInset` (it's `deviceTopInset + headingClearance`, plus
    /// the pinned-Obie zone) — so the device inset was counted TWICE and the first Take sat ~60pt
    /// too low (owner 2026-07-15: "the first Take should rest in the Obie's position"). Subtract
    /// what iOS is about to give back, so the NET top is exactly `topInset`.
    ///
    /// Do NOT "fix" this by setting `.never` instead: that bisected to a FATAL compositional-layout
    /// recursion (`_updateVisibleCellsNow` 7 deep → `_assertionFailure`) plus stuttery scroll —
    /// three device crashes, none before it (2026-07-16). Compensate; don't opt out.
    ///
    /// `bottomInset` is deliberately left uncompensated — it's what ships today and the dock end
    /// reads correctly; changing it isn't warranted by any observed problem.
    private func applyContentInsets() {
        let inset = UIEdgeInsets(top: max(0, topInset - collectionView.safeAreaInsets.top),
                                 left: 0, bottom: bottomInset, right: 0)
        if collectionView.contentInset != inset {
            collectionView.contentInset = inset
            collectionView.verticalScrollIndicatorInsets.top = inset.top
        }
    }

    func apply(groups: [TimelineMonthGroup]) {
        applyContentInsets()
        takesByID = Dictionary(groups.flatMap(\.takes).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        groupTitles = Dictionary(groups.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })

        var items: [TimelineRow] = []
        for (index, group) in groups.enumerated() {
            // Suppress the first group's divider (the DAILIES heading is its context) — EXCEPT
            // when it's the active filter month, so the amber "× MONTH" stays as the clear
            // affordance even once it's the only group left.
            if index > 0 || group.id == activeMonthKey { items.append(.month(group.id)) }
            items.append(contentsOf: group.takes.map { .take($0.id) })
        }

        // Re-apply the snapshot ONLY when the item list changed. SwiftUI re-renders DailiesView
        // many times during the new-Take bloom animation; re-applying an identical snapshot each
        // time churned collection layout and thrashed the keyboard placement (caps-flash, attempt 1).
        if items != lastItems {
            lastItems = items
            var snapshot = NSDiffableDataSourceSnapshot<Int, TimelineRow>()
            snapshot.appendSections([0])
            snapshot.appendItems(items, toSection: 0)
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        // Item identity is the id alone, so a CONTENT change (mark-done, saved edit) needs an
        // explicit reconfigure. Normally reconfigure ONLY the Takes whose value changed (Take
        // is Equatable). A density/spine SETTING change doesn't touch Take content but does
        // change every cell's layout, so reconfigure all in that case.
        let layoutChanged = spineX != lastSpineX || cardGap != lastCardGap
        lastSpineX = spineX; lastCardGap = cardGap
        // A month-filter change doesn't touch any Take's content, but it restyles the DIVIDERS
        // (the active one lights amber with an ×) — item identity is the id alone, so they need
        // an explicit reconfigure or the lit state never appears.
        let monthFilterChanged = lastActiveMonthKey != .some(activeMonthKey)
        lastActiveMonthKey = .some(activeMonthKey)
        let current = dataSource.snapshot()
        let toApply: [TimelineRow]
        if layoutChanged {
            toApply = current.itemIdentifiers
        } else {
            let changedIDs = Set(takesByID.compactMap { id, take in previousTakes[id] != take ? id : nil })
            toApply = current.itemIdentifiers.filter { row in
                switch row {
                case .take(let id): return changedIDs.contains(id)
                case .month: return monthFilterChanged
                }
            }
        }
        previousTakes = takesByID
        if !toApply.isEmpty {
            var reconfigured = current
            reconfigured.reconfigureItems(toApply)
            dataSource.apply(reconfigured, animatingDifferences: false)
        }
    }

    private var editingActive = false
    /// Fade + disable the whole collection while editing (cards recede, taps pass through to
    /// the save catcher behind). Matches the old timeline's row-mask dim, but applied to the
    /// UIKit view so it can't be defeated by representable compositing.
    func updateEditing(_ editing: Bool) {
        guard editing != editingActive else { return }
        editingActive = editing
        collectionView.isUserInteractionEnabled = !editing
        UIView.animate(withDuration: 0.22) { self.collectionView.alpha = editing ? 0.14 : 1 }
    }

    /// The take's cell frame in WINDOW coords (for anchoring the in-place editor). The cell
    /// is on-screen at tap time, so its layout attributes are available.
    private func cardFrameInWindow(for id: UUID) -> CGRect {
        guard let ip = dataSource.indexPath(for: .take(id)),
              let attr = collectionView.layoutAttributesForItem(at: ip) else { return .zero }
        return collectionView.convert(attr.frame, to: nil)   // nil = window
    }
}
