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
    /// Takes whose overdue reminder is SNOOZED — their label lane reads "SNOOZED" instead of
    /// "OVERDUE" (D-058/D-060). Not derivable from the Take: snooze lives in the view model
    /// (`vm.snoozedReminderIDs`), which is exactly why the rebuild lost it (see the VC's
    /// `snoozedIDs`).
    var snoozedIDs: Set<UUID> = []
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
    /// Tap the EMPTY timeline (off any cell) → the host clears a filter / closes search. The old
    /// SwiftUI timeline had this as a `.background` catcher; this collection covers that area.
    var onTapBackground: () -> Void = {}
    /// M4.6 — while editing, FADE + disable the collection itself (like the old timeline
    /// fades its rows to 0.12), so the cards recede and taps fall THROUGH to the save
    /// catcher behind. This avoids fighting the representable's compositing (the collection
    /// otherwise sits above the SwiftUI veil for hit-testing — tap-between-Takes was dead).
    var isEditing: Bool = false
    /// Task 6.19 — the Spotlight deep-link target (nil when none). The VC scrolls the row
    /// into view, pulses it, then fires `onRevealHandled` so the host clears the state.
    var revealTargetID: UUID? = nil
    var onRevealHandled: () -> Void = {}

    func makeUIViewController(context: Context) -> UIKitTimelineViewController {
        let vc = UIKitTimelineViewController()
        vc.spineX = spineX
        vc.cardGap = cardGap
        vc.activeMonthKey = activeMonthKey
        vc.onToggleMonthFilter = onToggleMonthFilter
        vc.snoozedIDs = snoozedIDs
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
        vc.onTapBackground = onTapBackground
        vc.onRevealHandled = onRevealHandled
        return vc
    }

    func updateUIViewController(_ vc: UIKitTimelineViewController, context: Context) {
        vc.spineX = spineX
        vc.cardGap = cardGap
        vc.activeMonthKey = activeMonthKey
        vc.onToggleMonthFilter = onToggleMonthFilter
        vc.snoozedIDs = snoozedIDs
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
        vc.onTapBackground = onTapBackground
        vc.onRevealHandled = onRevealHandled
        vc.apply(groups: groups)
        vc.updateEditing(isEditing)
        // After apply, so a target set while the data was still loading (e.g. a
        // Spotlight tap on the locked app) can resolve against the fresh rows.
        vc.requestReveal(revealTargetID)
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
    /// Overdue reminder currently SNOOZED → the label lane reads "SNOOZED" not "OVERDUE"
    /// (D-058/D-060). It can't be read off the Take — snooze lives in the view model — so it has
    /// to be threaded down. The rebuild simply never passed it, and every snoozed Take on the new
    /// timeline said OVERDUE (found 2026-07-16 while re-anchoring the Feature Register).
    var isSnoozed: Bool = false
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
    /// Task 6.19 — true while this row is the Spotlight deep-link target's pulse
    /// window (driven by the VC's `flashingID` via reconfigure). The card overlays
    /// a brief ember tint; `.animation(value:)` fades both edges.
    var isSpotlightTarget: Bool = false

    @Environment(\.colorScheme) private var scheme
    private let inset = CatchlightLayout.cardSpineInset
    private let d = CatchlightLayout.circleDiameter
    private let w = CatchlightLayout.spineWidth
    private var occW: CGFloat { CatchlightLayout.spineWidth + CatchlightLayout.spineTrackOffset * 2 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TakeCardSurface(take: take, isSnoozed: isSnoozed, linksInteractive: false)  // card
                // Task 6.19 — brief flash when this row is the Spotlight deep-link
                // target. The ember accent at low opacity reads as a gentle pulse,
                // not a notification (same treatment as the pinned Obie's flash in
                // DailiesView.rowContent). Render-only.
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.ckEmber.opacity(isSpotlightTarget ? 0.18 : 0))
                        .animation(.easeInOut(duration: 0.4), value: isSpotlightTarget)
                        .allowsHitTesting(false)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture { onTapText(take) }
                .contextMenu { menuItems }
                // ⚠️ VoiceOver + TEST CONTRACT. This cell draws `TakeCardSurface` DIRECTLY rather
                // than going through `TakeRowView`, so none of that view's accessibility came with
                // it — this timeline was unreadable to VoiceOver, and invisible to the XCUITests
                // that find a Take by the "take-row" identifier. It went unnoticed for six
                // milestones because the A/B toggle meant CI only ever drove the OLD timeline
                // (found when M7 flipped the default, PR #130). Labels are shared statics so the
                // two rows can't drift apart again.
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("take-row")
                .accessibilityLabel(TakeRowView.accessibilityLabel(for: take))
                .accessibilityHint("Double-tap to edit this Take.")
                .accessibilityActions { menuItems }
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
                .accessibilityElement()
                .accessibilityIdentifier("take-iris")
                .accessibilityLabel(TakeRowView.irisAccessibilityLabel(for: take))
                .accessibilityHint(take.isObie
                    ? "Double-tap to open actions. Long press to turn this back into a standard Take."
                    : "Double-tap to open actions. Long press to make this your Obie.")
                // VoiceOver intercepts long-press, so the Obie toggle needs a named action too.
                .accessibilityAction(named: take.isObie ? "Make standard Take" : "Make Obie") {
                    onLongPressCircle(take)
                }
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
    /// Threaded straight through to `TimelineReadCell` (see its `isSnoozed`).
    var isSnoozed: Bool = false
    @Bindable var swipeState: TimelineSwipeState
    let onToggleDone: (Take) -> Void
    let onDelete: (Take) -> Void
    var onTapCircle: (Take, CGPoint) -> Void = { _, _ in }
    var onLongPressCircle: (Take) -> Void = { _ in }
    var onSetImportant: (Take) -> Void = { _ in }
    var onMakeObie: (Take) -> Void = { _ in }
    var onExport: (Take) -> Void = { _ in }
    var onTapText: (Take) -> Void = { _ in }
    /// Threaded straight through to `TimelineReadCell` (see its `isSpotlightTarget`).
    var isSpotlightTarget: Bool = false

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
                             isSnoozed: isSnoozed,
                             onTapCircle: onTapCircle, onLongPressCircle: onLongPressCircle,
                             onToggleDone: onToggleDone, onDelete: onDelete,
                             onSetImportant: onSetImportant, onMakeObie: onMakeObie,
                             onExport: onExport, onTapText: onTapText,
                             isSpotlightTarget: isSpotlightTarget)
                .offset(x: offset)
        }
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
    /// TAP the LABEL to filter the timeline to this creation month; tap the lit one again to clear.
    var onTap: () -> Void = {}
    /// Tap the blank space beside the label → the host's background action (clear a filter / close
    /// search), so this row reads as timeline background rather than a dead strip (owner
    /// 2026-07-16). The collection's own background tap can't do it: this row IS a cell, so that
    /// recognizer is gated off here.
    var onTapBlank: () -> Void = {}
    var body: some View {
        HStack(spacing: 6) {
            // Only the LABEL takes the tap — not the whole row (owner 2026-07-16). The row runs
            // the full width (the Spacer sets the divider's rhythm), so a row-wide target meant a
            // tap in the empty space to the right silently filtered the timeline. The vertical
            // padding sits INSIDE the target, so the touch height is still the full row.
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
            }
            .padding(.vertical, cardGap / 2)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isActive
                ? "\(title), filtering. Double-tap to clear."
                : "\(title). Double-tap to show only Takes created this month.")
            // The rest of the row reads as timeline background: tapping it exits a Sequence, the
            // same as tapping any empty space. `Color.clear` rather than `Spacer` — a Spacer has
            // no content to hit-test, so it can't carry the gesture. Fills the row's height (set
            // by the label's vertical padding) so the whole strip is live.
            Color.clear
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTapBlank)
                .accessibilityHidden(true)
        }
        .padding(.leading, spineX - CatchlightLayout.cardSpineInset + CatchlightLayout.cardTextLeadingPad)
        .padding(.trailing, 20)
    }
}

final class UIKitTimelineViewController: UIViewController, UIGestureRecognizerDelegate {
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
    var onTapBackground: () -> Void = {}

    private let swipeState = TimelineSwipeState()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, TimelineRow>!
    private var takesByID: [UUID: Take] = [:]
    private var previousTakes: [UUID: Take] = [:]   // reconfigure only what changed
    private var lastItems: [TimelineRow] = []        // skip re-applying an unchanged snapshot
    private var lastSpineX: CGFloat = -1             // density/spine change → reconfigure all
    private var lastCardGap: CGFloat = -1
    private var lastActiveMonthKey: String??        // month-filter change → restyle the dividers
    /// Snoozed Take ids (from the host's view model). A snooze does NOT change the `Take`, so the
    /// value-diff reconfigure below can't see it — it needs its own trigger, like the month filter.
    var snoozedIDs: Set<UUID> = []
    private var lastSnoozedIDs: Set<UUID>?
    private var groupTitles: [String: String] = [:]

    @objc private func handleBackgroundTap() { onTapBackground() }

    /// Only let the background tap see touches that land OFF a cell — a tap on a card, its Iris,
    /// or a month divider belongs to that cell's own recognizers.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        collectionView.indexPathForItem(at: touch.location(in: collectionView)) == nil
    }

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
        // Tap the EMPTY timeline → the host's background action (clear a filter / close search).
        // The old SwiftUI timeline did this with a `.background` catcher behind its VStack; this
        // collection covers that area and eats the tap, so the exit was lost in the rebuild —
        // leaving a Sequence with no way out (owner 2026-07-16).
        //
        // Gated in `gestureRecognizerShouldReceive` rather than by testing the hit inside the
        // handler: the cells carry their own tap / Iris / swipe / context-menu recognizers, and
        // this must never engage alongside them. Off a cell there is nothing to compete with.
        let backgroundTap = UITapGestureRecognizer(target: self,
                                                   action: #selector(handleBackgroundTap))
        backgroundTap.delegate = self
        collectionView.addGestureRecognizer(backgroundTap)
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
                                      isSnoozed: self.snoozedIDs.contains(id),
                                      swipeState: self.swipeState,
                                      onToggleDone: { self.onToggleDone($0) },
                                      onDelete: { self.onDelete($0) },
                                      onTapCircle: { self.onTapCircle($0, $1) },
                                      onLongPressCircle: { self.onLongPressCircle($0) },
                                      onSetImportant: { self.onSetImportant($0) },
                                      onMakeObie: { self.onMakeObie($0) },
                                      onExport: { self.onExport($0) },
                                      onTapText: { [weak self] tapped in
                                          self?.onTapText(tapped)
                                      },
                                      isSpotlightTarget: self.flashingID == id)
                }
                .margins(.all, 0)
            case .month(let key):
                cell.contentConfiguration = UIHostingConfiguration {
                    TimelineMonthDivider(title: self.groupTitles[key] ?? "",
                                         spineX: self.spineX, cardGap: self.cardGap,
                                         isActive: self.activeMonthKey == key,
                                         onTap: { self.onToggleMonthFilter(key) },
                                         onTapBlank: { self.onTapBackground() })
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
        // Snoozing doesn't touch a Take's VALUE (it lives in the view model), so the value-diff
        // below would never restyle the card — the lane would keep saying OVERDUE. Diff the SET.
        let snoozeChanged = lastSnoozedIDs != nil && lastSnoozedIDs != snoozedIDs
        let snoozeAffected = (lastSnoozedIDs ?? []).symmetricDifference(snoozedIDs)
        lastSnoozedIDs = snoozedIDs
        let current = dataSource.snapshot()
        let toApply: [TimelineRow]
        if layoutChanged {
            toApply = current.itemIdentifiers
        } else {
            var changedIDs = Set(takesByID.compactMap { id, take in previousTakes[id] != take ? id : nil })
            if snoozeChanged { changedIDs.formUnion(snoozeAffected) }
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

        // A reveal may be waiting for its row (Spotlight tap while LOCKED lands
        // before the store opens) — this apply may just have delivered it.
        attemptReveal()
    }

    // MARK: - Spotlight deep-link reveal (Task 6.19, re-wired for the UIKit timeline 2026-07-23)
    //
    // The SwiftUI timeline's scroll-and-flash died in the M7 rewrite: the host set
    // `ui.spotlightTargetTakeID` but nothing in this collection consumed it (only
    // the pinned-Obie row path did, and nothing ever cleared it). The host now
    // hands the target to `requestReveal`; this scrolls the row into view, pulses
    // the card via `flashingID` → reconfigure → the cell's ember overlay, and
    // fires `onRevealHandled` so the host clears the one-shot state.

    /// Fired (async) once a reveal has been actioned — the host clears
    /// `ui.spotlightTargetTakeID` so a later re-tap of the same Take re-targets.
    var onRevealHandled: () -> Void = {}
    /// The row currently pulsing ember (read by the cell registration).
    private var flashingID: UUID?
    /// A reveal whose row is not in the snapshot yet. Held until `apply` delivers
    /// it; deliberately never times out — for a Take that no longer exists
    /// (Spotlight raced the deindex) it simply never fires.
    private var pendingRevealID: UUID?
    /// The last target accepted, so the host's repeated `updateUIViewController`
    /// passes (the one-shot state clears asynchronously) don't re-trigger the
    /// scroll. Reset when the host's target clears to nil.
    private var lastRequestedRevealID: UUID?

    func requestReveal(_ id: UUID?) {
        guard let id else { lastRequestedRevealID = nil; return }
        guard id != lastRequestedRevealID else { return }
        lastRequestedRevealID = id
        pendingRevealID = id
        attemptReveal()
    }

    private func attemptReveal() {
        guard let id = pendingRevealID, dataSource != nil,
              let indexPath = dataSource.indexPath(for: .take(id)) else { return }
        pendingRevealID = nil
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
        // Pulse once the scroll has settled, hold ~1s, fade out — the cell overlay's
        // `.animation(value:)` animates both edges.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.setFlashing(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.setFlashing(nil)
            }
        }
        // Clear the host's one-shot target OUTSIDE the current SwiftUI update pass
        // (attemptReveal can run inside updateUIViewController via apply).
        DispatchQueue.main.async { [weak self] in self?.onRevealHandled() }
    }

    /// Flip the pulse on/off by reconfiguring only the affected row(s).
    private func setFlashing(_ id: UUID?) {
        let affected = [flashingID, id].compactMap { $0 }.map { TimelineRow.take($0) }
        flashingID = id
        var snapshot = dataSource.snapshot()
        let present = affected.filter { snapshot.itemIdentifiers.contains($0) }
        guard !present.isEmpty else { return }
        snapshot.reconfigureItems(present)
        dataSource.apply(snapshot, animatingDifferences: false)
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

}
