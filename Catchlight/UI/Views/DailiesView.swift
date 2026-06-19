//
//  DailiesView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  The homepage timeline — the ONE surface (dock redesign 2026-06-10). A vertical
//  scroll of TakeRowViews threaded by a 2px spine aligned to each circle's centre.
//  The Obie (if any) is pinned at the top with a small gap before the regular
//  list — ALWAYS, even when it doesn't match the active filter. Month markers
//  ghost in only while scrolling (they are never static). First-launch empty
//  state is a single Fog line.
//
//  Live filtering (2026-06-10): the dock's FILTERING toggles and SEARCHING query
//  produce `ui.activeTimelineFilter`; the non-Obie rows are narrowed through
//  `SequenceFilter.matches` before month-grouping. When a filter is active but
//  nothing matches, a quiet "Nothing here yet." line replaces the grouped list.
//  In FILTERING, tapping empty timeline background (not rows/Irises) exits to
//  RESTING and clears all filters.
//
//  Petal fan and edit surfaces are presented by the parent RootView via the shared
//  UIState, so this view stays focused on layout + the spine geometry.
//
//  Task 3.9: Error and edge-case states — three quiet, non-blocking strips are
//  inserted above the timeline via `.safeAreaInset(edge: .top)`: storage error,
//  sync error, and quarantine notice. All share the conflict-banner geometry
//  (44pt, 16pt horizontal pad, same font) so the visual vocabulary stays consistent.
//

import SwiftUI
import CatchlightCore

struct DailiesView: View {
    @Environment(DailiesViewModel.self) private var vm
    @Environment(UIState.self) private var ui
    @Environment(AppModel.self) private var app
    @Environment(FirstRunOrientationState.self) private var orientation
    @Environment(ConflictQueue.self) private var conflicts
    @Environment(\.colorScheme) private var scheme

    /// Container width, captured by the background GeometryReader on the body
    /// ZStack; drives `spineX`.
    @State private var containerWidth: CGFloat = 0


    /// Horizontal centre of the circles == x of the spine == the dock's Add
    /// button centre. Both derive from `CatchlightLayout.spineX(containerWidth:)`
    /// — the same four-equal-columns formula BottomDockView lays out with — so
    /// the spine sits exactly on the + vertical at every device width
    /// (2026-06-10 fix: the previous fixed 32pt constant never matched the
    /// dock). The screen width stands in before the first layout pass so the
    /// spine doesn't flash at a wrong x.
    private var spineX: CGFloat {
        CatchlightLayout.spineX(
            containerWidth: containerWidth > 0 ? containerWidth : UIScreen.main.bounds.width
        )
    }

    /// Left edge of the Take TEXT column — the card's left edge (`spineX −
    /// cardSpineInset`) plus the card's internal leading pad. The DAILIES heading and
    /// the ghosted month markers align to this so they sit directly above the body
    /// text (owner 2026-06-16; was `spineX + 22`, which floated them right of the text).
    private var textColumnLeading: CGFloat {
        spineX - CatchlightLayout.cardSpineInset + CatchlightLayout.cardTextLeadingPad
    }

    /// Reads the user's timeline-density choice live. The inter-card LazyVStack
    /// spacing is the chosen clear gap MINUS the two 6pt row paddings each card
    /// already carries (`.padding(.vertical, 6)`), so the visible card-to-card gap
    /// equals `TakeSpacing.gap`.
    @AppStorage(SettingsViewModel.TakeSpacing.defaultsKey)
    private var takeSpacingRaw: String = SettingsViewModel.TakeSpacing.default.rawValue
    private var takeSpacing: SettingsViewModel.TakeSpacing {
        SettingsViewModel.TakeSpacing(rawValue: takeSpacingRaw) ?? .default
    }
    /// LazyVStack spacing + the Obie gap. `gap − 12` because each row adds 6pt top
    /// and 6pt bottom of its own; the result is the extra space between cards.
    private var interCardSpacing: CGFloat { max(0, takeSpacing.gap - 12) }

    /// Timeline order (owner 2026-06-16). Default Oldest first: oldest at the top,
    /// newer Takes accrue below. The Obie stays pinned above the list regardless.
    @AppStorage(SettingsViewModel.TakeSort.defaultsKey)
    private var takeSortRaw: String = SettingsViewModel.TakeSort.default.rawValue
    private var takeSort: SettingsViewModel.TakeSort {
        SettingsViewModel.TakeSort(rawValue: takeSortRaw) ?? .default
    }

    @State private var scrolling = false
    @State private var scrollHideWork: DispatchWorkItem?
    /// "Rings on a wire" texture (owner idea 2026-06-16): a STATIC dotted line laid
    /// over the solid spine. As the rings scroll past the fixed dots, the eye reads
    /// them sliding over a marked wire (relative motion at the true 1× scroll speed) —
    /// no animation, the spine layer doesn't scroll, so static dots are all it takes.
    ///
    /// The dotted frame is anchored to `spineTopInset` — the SAME top as the solid
    /// spine, so it begins exactly at the top Take (owner 2026-06-16). To keep the
    /// dots screen-static even while that frame top tracks the first row (the no-Obie
    /// case), the dash phase compensates by `+spineTopInset`: a dash lands at
    /// screen-y `frameTop + (−phase + k·period)` = `k·period`, independent of the
    /// frame top, so the dots hold fixed positions while the line still starts at the
    /// top Take. (With an Obie, `spineTopInset` is constant and this is just a static
    /// offset.) The sign MUST be `+`: `−` advances the phase the wrong way and the
    /// dots slide at ~2× — the bug that put two dotted wires on screen at once.
    private var dottedSpinePhase: CGFloat { spineTopInset }
    /// The row currently showing its swipe actions (Delete / Mark done), if any.
    /// Shared across rows so opening one closes the rest (`SwipeActionRow`).
    @State private var openSwipeRowID: UUID?
    /// The first row's top Y in the "dailies" space, published by the first row so
    /// the spine starts exactly at the first Iris (handles the pinned-Obie vs
    /// invisible-month-marker offset). `nil` until the first layout pass.
    @State private var firstRowTop: CGFloat?
    /// Measured height of the pinned Obie zone (the Obie row + its 12pt fade), used
    /// to inset the scrolling Takes below it. 0 ⇒ no Obie / not yet measured.
    @State private var pinnedObieZoneHeight: CGFloat = 0

    // MARK: - Edit-in-place (2026-06-17)
    /// The live draft of the Take being edited in position, and which of its blocks
    /// holds the keyboard. `ui.editingTakeID` is the matching focus flag (shared so
    /// RootView can mask the dock). Both clear on save/discard. The draft is committed
    /// through the same `vm.save` chokepoint the top-anchored editor uses.
    @State private var editDraft: Take?
    @State private var editFocusedBlockID: UUID?
    /// Drives the "Make this your Obie?" confirmation when the Focus ring turns Obie
    /// on (inline) while another Obie already exists — the same warning the timeline
    /// long-press uses, but targeting the draft (owner 2026-06-17).
    @State private var pendingInlineObieConfirm = false
    /// One-shot scroll target — set to bring a Take into view (e.g. a new Take that
    /// landed at the bottom under Oldest-first). The timeline's ScrollViewReader
    /// consumes and clears it.
    @State private var scrollToTakeID: UUID?
    /// Bloom progress (0→1) for the in-place NEW Take's "appear". Driven explicitly
    /// (scale+opacity on the row) rather than via a LazyVStack insertion transition,
    /// which doesn't animate reliably. 1 at rest so existing rows are unaffected.
    @State private var newTakeBloom: Double = 1
    /// Whether the full-screen Angle is presented over the in-place editor. INTERIM
    /// (2026-06-18) — the Angle's eventual entry point is the right-side selector ring;
    /// this keeps it reachable for review until that's built. Bound to the live
    /// `editDraft` so its ticks / reorders / deletes ride the inline save.
    @State private var anglePresented = false

    /// Extra bottom scroll room added while editing so the focused Take — even the
    /// last one under Oldest-first — can scroll up to its clear position above the
    /// keyboard rather than clamping against the content end (owner 2026-06-19).
    /// A generous screen fraction; it's empty space below the keyboard, never seen.
    private let editScrollRoom: CGFloat = 420

    /// Where the spine's top edge sits: the first Iris's top edge. Prefer the
    /// MEASURED first-row top; before the first layout, fall back to the constant
    /// estimate (no month marker). Row top → card top (+6, the Iris straddles the
    /// top edge so its centre is there) → Iris top (−radius).
    private var spineTopInset: CGFloat {
        let radius = CatchlightLayout.circleDiameter / 2
        // With an Obie, it's PINNED at the standard first-item position
        // (`deviceTopInset + headingClearance`), so the wire begins right there — the
        // same formula as the no-row fallback. Without one, it starts at the first
        // scrolling row.
        if vm.obie != nil {
            return deviceTopInset + CatchlightLayout.headingClearance + 6 - radius
        }
        if let t = firstRowTop, t.isFinite {
            return max(0, t + 6 - radius)
        }
        return deviceTopInset + CatchlightLayout.headingClearance + 6 - radius
    }

    /// The scroll's top inset. Without an Obie it's the plain heading clearance.
    /// With one, it clears the pinned Obie row AND leaves the same visible gap the
    /// "View" setting puts between two Takes — each card's 6pt top/bottom padding
    /// already accounts for ~12pt of that, so we add the remainder.
    private var timelineTopInset: CGFloat {
        let base = deviceTopInset + CatchlightLayout.headingClearance
        guard vm.obie != nil, pinnedObieZoneHeight > 0 else { return base }
        return base + pinnedObieZoneHeight + max(0, takeSpacing.gap - 12)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.ckBackground.ignoresSafeArea()

            // The spine: a hairline behind the rows, at the circle centre. It
            // STARTS at the first Iris's top edge (HiFi §1 "the spine terminates at
            // the first Take") rather than the screen top — a full-height line poked
            // up into the gap below the DAILIES heading. First Iris centre = the
            // timeline's top content pad (deviceTopInset + headingClearance) + the
            // row's 6pt vertical pad; the top edge is one Iris radius higher. The
            // bottom runs on toward the Add button, covered by the dock fade (HiFi).
            Rectangle()
                // Owner 2026-06-16: the spine takes the dock buttons' ring colour
                // (Ember @ 35% — `dockRing()` in BottomDockView) so the wire and the
                // toolbar read as one family. (Was `ckSpine`, a fainter Catchlight/Ink
                // tint; that token still serves onboarding + the conflict view.)
                // Single-sourced via `ckSpineWire` so the gutter spine and the
                // through-Iris segments (TakeRowView, "rings on a wire") never drift.
                .fill(Color.ckSpineWire)
                // Fully hidden while editing in place (owner 2026-06-17): a thin line
                // reads as a "remnant" even at the 0.12 row-mask — especially once the
                // Obie card (which used to cover it) goes invisible, exposing the spine
                // at the empty Obie position. The faint masked CARDS carry the
                // "part of the timeline" feel; the connecting wire isn't needed in focus.
                .opacity(ui.isEditingInPlace ? 0 : 1)
                .frame(width: CatchlightLayout.spineWidth)
                .frame(maxHeight: .infinity)
                .padding(.top, spineTopInset)
                // Terminate the spine at the TOP EDGE of the Add button's ring rather
                // than running full-bleed under the dock (owner 2026-06-16: it was
                // visible through the +'s hollow ring). The Add ring's top sits
                // `dockBottomPadding + minTouchTarget` above the device bottom inset
                // (BottomDockView lays the 44pt button `dockBottomPadding` above the
                // home indicator), so the wire plugs into the top of the +.
                .padding(.bottom, deviceBottomInset
                         + CatchlightLayout.dockBottomPadding
                         + CatchlightLayout.minTouchTarget)
                .offset(x: spineX - CatchlightLayout.spineWidth / 2)
                .accessibilityHidden(true)

            // Owner idea 2026-06-16 — a STATIC dotted line laid OVER the solid spine.
            // The dots never move; because this whole spine layer sits BEHIND the
            // scrolling cards, the rings scroll past the fixed dots and the eye reads
            // them sliding over a marked wire. Same x + z + footprint as the solid
            // spine (behind the cards, visible only in the gaps), so it never paints
            // over a card; brighter than the 35% base so the dots read. Anchored to
            // `spineTopInset` (begins at the top Take, like the solid spine) with the
            // dash phase compensating so the dots stay screen-static (see
            // `dottedSpinePhase`).
            DottedSpine(dashPhase: dottedSpinePhase)
                // Fully hidden while editing in place (with the solid spine, above).
                .opacity(ui.isEditingInPlace ? 0 : 1)
                .frame(width: CatchlightLayout.spineWidth)
                .frame(maxHeight: .infinity)
                .padding(.top, spineTopInset)
                .padding(.bottom, deviceBottomInset
                         + CatchlightLayout.dockBottomPadding
                         + CatchlightLayout.minTouchTarget)
                .offset(x: spineX - CatchlightLayout.spineWidth / 2)
                .accessibilityHidden(true)

            // A first-launch-empty store shows the Fog line; but when a dock
            // filter is active the timeline (with its own filter-empty line)
            // always wins, so the background-tap exit remains available.
            if vm.isEmpty && activeFilter.isEmpty && inlineNewTake == nil {
                emptyState
            } else {
                timeline
            }

            // Pinned page heading + top fade (cosmetic baseline 2026-06-11):
            // a plain overlay child, NOT .safeAreaInset — in this full-bleed
            // hierarchy (.ignoresSafeArea(.container) at the app root) a top
            // safeAreaInset here desynced hit-testing and killed the dock's
            // keyboard avoidance (Flow 5 regression, 2026-06-11). The heading
            // dodges the status bar itself via deviceTopInset. Takes scroll
            // under the solid block and dissolve beneath the 12pt fade.
            // While editing in place (owner 2026-06-17) the heading's page-coloured
            // top MASK stays opaque — so a focused Take scrolled up still dissolves
            // under it instead of running to the Dynamic Island — and only the title
            // TEXT dims (the dimming lives on `Text(headingTitle)` inside `heading`).
            heading

            // The pinned Obie sits below the heading at the first-Take position, with
            // its own solid backing + fade; scrolling Takes pass behind it and dissolve.
            // Drawn after the heading so it owns its hit region (the heading is inert).
            pinnedObie
        }
        .background {
            // Capture the layout width (NOT UIScreen) so spineX matches the
            // dock, which is laid out in the same safe-area coordinate space —
            // and the remaining top safe-area inset for the pinned heading.
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in containerWidth = width }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { topStrips }
        .animation(.easeInOut(duration: 0.2), value: conflicts.pending.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: vm.lastError)
        .animation(.easeInOut(duration: 0.2), value: app.lastSyncError)
        .animation(.easeInOut(duration: 0.2), value: app.quarantinedCount)
        .onAppear {
            vm.reload()
            // Kick off the first-run orientation tour the first time the main app
            // is visible. No-op once the tour has started or completed.
            orientation.beginIfNeeded()
            // Let AppModel.relock save a mid-edit Take through our save path before it
            // tears down the store (owner 2026-06-17 — lock auto-saves, never discards).
            ui.commitInlineEdit = { saveInlineEdit() }
        }
        .onDisappear { ui.commitInlineEdit = nil }
        // The Focus ring committed while a Take is edited in place — apply it to the
        // live draft (edit-in-place 2026-06-17). Guarded on `editingTakeID` so the
        // (behind) timeline ignores commits meant for the top-anchored new-Take editor.
        .onChange(of: ui.inlineFanCommand) { _, command in
            guard let command, ui.editingTakeID != nil else { return }
            applyInlineFanCommand(command)
            ui.inlineFanCommand = nil
        }
        // Dock + requested a new Take (Phase 2): create it in place at the
        // Order-appropriate end and focus it.
        .onChange(of: ui.pendingInlineNewTake) { _, take in
            guard let take else { return }
            beginNewInlineEdit(take)
            ui.pendingInlineNewTake = nil
        }
        // Inline Obie confirmation — mirrors the timeline long-press warning, but
        // targets the draft (the existing Obie is demoted by the store on save).
        .alert("Make this your Obie?", isPresented: $pendingInlineObieConfirm) {
            Button("Make Obie") { confirmInlineObie() }
            Button("Cancel", role: .cancel) { cancelInlineObie() }
        } message: {
            Text("Your existing Obie returns to the timeline — only one Take can be your Obie.")
        }
        // Interim Angle entry (2026-06-18): the full-screen list Angle, opened from the
        // editor's top-right affordance, bound to the live draft so ticks / reorders /
        // deletes ride the inline save. (Final entry point will be the selector ring.)
        .fullScreenCover(isPresented: $anglePresented) {
            angleCover
        }
    }

    // MARK: - Heading

    /// The device's top safe-area inset, captured at the WINDOW ROOT in
    /// CatchlightApp and delivered via the environment. The app root runs
    /// full-bleed (`.ignoresSafeArea(.container)` — the dock design), so the
    /// local safe-area plumbing reports zero here and the heading must dodge
    /// the status bar / Dynamic Island itself.
    ///
    /// History (2026-06-11): do NOT read UIKit window state for this —
    /// `keyWindow` per-body flapped when the keyboard window became key
    /// (killed dock hit-testing + keyboard avoidance); a `static let`
    /// UIApplication read trapped in dispatch_once recursion (launch SIGILL).
    /// The root-GeometryReader environment value is the safe source.
    @Environment(\.deviceTopInset) private var deviceTopInset

    /// The device's BOTTOM safe-area inset (home-indicator zone), captured at the
    /// window root (section 4 / D-041). Used to lift the timeline's last-row
    /// dock clearance so the final Take still clears the now-raised dock.
    @Environment(\.deviceBottomInset) private var deviceBottomInset

    /// The page title follows the activity: DAILIES · SEQUENCE · SEARCH.
    private var headingTitle: String {
        switch ui.dockMode {
        case .resting:   return "DAILIES"
        case .filtering: return "SEQUENCE"
        case .searching: return "SEARCH"
        }
    }

    /// Solid background behind the title, then a 12pt fade hugging it (kept
    /// tight so the pinned Obie's circle is clear of it at rest).
    private var heading: some View {
        VStack(spacing: 0) {
            HStack {
                Text(headingTitle)
                    // ROMAN (upright) display face — section 3. The page heading
                    // is Cormorant Garamond Light ROMAN, not the italic display
                    // cut. Take body text stays italic via `display(size:)`.
                    .font(CatchlightFont.displayRoman(size: 20, relativeTo: .title3))
                    .kerning(1.6)
                    .foregroundStyle(Color.ckTextPrimary)
                    // Recede the title while editing in place; the mask below stays
                    // opaque so scrolled-up content still dissolves under the top.
                    .opacity(ui.isEditingInPlace ? 0.12 : 1)
                    .id(headingTitle)
                    .transition(.opacity)
                Spacer()
            }
            .padding(.leading, textColumnLeading)
            .padding(.top, deviceTopInset + 14)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.ckBackground)
            if vm.obie != nil && !ui.isEditingInPlace {
                // With a pinned Obie: SOLID right down to the Obie's card top (no fade
                // — the gradient is semi-transparent and lets a scrolling Take peek).
                // The opaque Obie card continues the mask below. Its own Iris is drawn
                // ON TOP of the heading, so this doesn't cover it (owner 2026-06-16).
                Color.ckBackground
            } else {
                // No Obie — OR editing in place (owner 2026-06-17): use the natural
                // height + a 12pt fade so a grown focused Take dissolves under the
                // top, exactly like the no-Obie timeline, instead of vanishing at the
                // Obie heading's hard mid-screen edge. (The pinned Obie + insets stay
                // put, so the focused Take's position doesn't jump.)
                LinearGradient(
                    colors: [Color.ckBackground, Color.ckBackground.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 12)
            }
        }
        // ONLY when an Obie is pinned, the solid mask extends down to NEAR the Obie's
        // card BOTTOM edge (owner 2026-06-16) — not the top edge, because the card's
        // rounded top corners curve below it and leave a sliver where scrolling Takes
        // peeked. Anchoring to the bottom (measured, so it scales with a long Obie)
        // guarantees every corner is above the mask edge. The −12 pulls the mask edge
        // up 12px from the true bottom (owner 2026-06-17: a 6px nudge up from the prior
        // −6 to clear a small scroll-edge ugliness). Natural height when there's no Obie.
        .frame(height: (vm.obie != nil && !ui.isEditingInPlace)
                       ? deviceTopInset + CatchlightLayout.headingClearance + max(0, pinnedObieZoneHeight - 12)
                       : nil,
               alignment: .top)
        .animation(.easeInOut(duration: 0.18), value: headingTitle)
        .allowsHitTesting(false)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(headingTitle.capitalized)
    }

    /// The PINNED Obie (owner 2026-06-16) — a static element sitting at the SAME
    /// position a plain first Take would (`deviceTopInset + headingClearance`), so the
    /// top item is in the same place with or without an Obie. Scrolling Takes pass
    /// behind its solid background and dissolve under the fade below it. It keeps its
    /// swipe actions, so it stays interactive (the heading title/fade above do not).
    @ViewBuilder
    private var pinnedObie: some View {
        if let obie = vm.obie {
            // The Obie's own card is OPAQUE, so it alone hides Takes scrolling up
            // behind it — no solid backing and no fade (both read as a page-coloured
            // band obscuring the timeline + spine; owner 2026-06-16).
            row(for: obie, isFirst: false)
                // Pin to natural height — the swipe fill is `maxHeight: .infinity`,
                // which would otherwise stretch this to fill the screen out here.
                .fixedSize(horizontal: false, vertical: true)
                .id(obie.id)
                // Measure the Obie row so the scrolling Takes inset below it.
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { pinnedObieZoneHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, h in pinnedObieZoneHeight = h }
                    }
                )
                // Sit at the standard first-item position (matches a plain first Take).
                .padding(.top, deviceTopInset + CatchlightLayout.headingClearance)
                // While editing ANOTHER Take, the pinned Obie goes fully invisible
                // (not just the row's 0.12 mask) — it sits ON TOP of the scroll, so at
                // 12% a focused Take scrolling behind it reads as a ghost (owner
                // 2026-06-17). Hidden, not removed, so it fades with the mask and its
                // measured height (the scroll inset) is preserved — no position jump.
                // When the Obie ITSELF is the focused Take it stays bright (editing it).
                .opacity(ui.isEditingInPlace && ui.editingTakeID != obie.id ? 0 : 1)
                .allowsHitTesting(!(ui.isEditingInPlace && ui.editingTakeID != obie.id))
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Text("Your first Take is waiting.")
            .font(CatchlightFont.ui(.light, size: 17, relativeTo: .body))
            .foregroundStyle(Color.ckTextSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Your first Take is waiting.")
    }

    // MARK: - Timeline

    /// Stack of quiet, non-blocking notice strips inserted above the timeline.
    /// Order (top → bottom): conflicts (Task 6.15), storage error, sync error,
    /// quarantine notice (Task 3.9). All share the conflict banner's geometry.
    private var topStrips: some View {
        VStack(spacing: 0) {
            conflictBanner
            lapseBanner
            storageErrorStrip
            syncErrorStrip
            quarantineNoticeStrip
        }
    }

    /// Read-only banner shown while the user is `.lapsed` (Tasks 6.20 / 6.22).
    /// Offers two parallel actions: resubscribe (opens the paywall) and export
    /// (subscription-independent — never gated). This is the lapse-mode entry
    /// point the decisions doc §5 specifically calls out.
    @ViewBuilder
    private var lapseBanner: some View {
        if app.subscriptionStatus == .lapsed {
            HStack(spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.ckAccent)
                    .accessibilityHidden(true)
                Text("Read-only — your data is still yours.")
                    .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Color.ckTextPrimary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button {
                    let takes = (try? vm.store.allTakes()) ?? []
                    ExportCoordinator.presentShareSheet(takes: takes)
                } label: {
                    Text("Export")
                        .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .body))
                        .foregroundStyle(Color.ckAccent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lapse-banner-export")
                .accessibilityLabel("Export your Takes")
                Button {
                    ui.isPaywallPresented = true
                } label: {
                    Text("Subscribe")
                        .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .body))
                        .foregroundStyle(Color.ckAccent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lapse-banner-subscribe")
                .accessibilityLabel("Resubscribe to Catchlight")
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(scheme == .dark
                        ? Color.ckGlow.opacity(0.12)
                        : Color.ckEmber.opacity(0.15))
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }

    /// Quiet amber banner at the top of the timeline shown while conflicts await
    /// resolution. Inserted via `.safeAreaInset(edge: .top)` so the timeline rows
    /// shift down cleanly rather than overlapping. (Task 6.15)
    @ViewBuilder
    private var conflictBanner: some View {
        let count = conflicts.pending.count
        if count > 0 {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.ckAccent)
                    .accessibilityHidden(true)
                // L10N: pluralisation done inline via `count == 1`. Future
                // pass should move to a Stringsdict / .xcstrings plural rule
                // — many locales don't pluralise on the singular/plural axis
                // alone (e.g. Polish, Arabic). Tracked but not blocking.
                Text("\(count) Take\(count == 1 ? "" : "s") changed on another device.")
                    .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Color.ckTextPrimary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button {
                    ui.isConflictSheetPresented = true
                } label: {
                    Text("Review")
                        .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .body))
                        .foregroundStyle(Color.ckAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(count) Take\(count == 1 ? "" : "s") changed on another device. Double-tap to review.")
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(scheme == .dark
                        ? Color.ckGlow.opacity(0.12)
                        : Color.ckEmber.opacity(0.15))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Task 3.9 error strips

    /// Shared chrome for every non-blocking strip on the timeline. Identical
    /// geometry to the conflict banner; only colour, icon and copy differ.
    private func noticeStrip(icon: String,
                             text: String,
                             tint: Color,
                             background: Color,
                             accessibilityLabel: String,
                             onDismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .subheadline))
                .foregroundStyle(Color.ckTextPrimary)
                .lineLimit(2)
                // Compose the message + Dismiss button into one VO element so the
                // user hears the full notice and then lands on the action, instead
                // of stepping through "exclamationmark, body text, Dismiss" hops.
                .accessibilityLabel("\(accessibilityLabel). \(text)")
                .accessibilityAddTraits(.isStaticText)
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Text("Dismiss")
                    .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .body))
                    .foregroundStyle(tint)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss \(accessibilityLabel)")
            .accessibilityHint("Double-tap to dismiss this notice.")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity)
        .background(background)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Storage-failure strip — fired by failures bubbled through `DailiesViewModel.lastError`.
    /// Auto-dismisses after 5 seconds.
    @ViewBuilder
    private var storageErrorStrip: some View {
        if let message = vm.lastError {
            noticeStrip(
                icon: "exclamationmark.circle",
                text: message,
                tint: Color.ckRuby,
                background: Color.ckRuby.opacity(0.12),
                accessibilityLabel: "storage error",
                onDismiss: { vm.clearError() }
            )
            .task(id: message) {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if vm.lastError == message { vm.clearError() }
            }
        }
    }

    /// Sync-failure strip — friendly summary set by `AppModel.reportSyncError`.
    /// Auto-dismisses after 8 seconds (longer than storage because the user has
    /// less context for what's happening in the background).
    @ViewBuilder
    private var syncErrorStrip: some View {
        if let message = app.lastSyncError {
            noticeStrip(
                icon: "exclamationmark.circle",
                text: message,
                tint: Color.ckRuby,
                background: Color.ckRuby.opacity(0.12),
                accessibilityLabel: "sync error",
                onDismiss: { app.clearSyncError() }
            )
            .task(id: message) {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if app.lastSyncError == message { app.clearSyncError() }
            }
        }
    }

    /// Quarantine notice — surfaces when `pullInbound()` skipped one or more
    /// Takes due to HMAC failure. UUIDs are NOT exposed; only a count.
    @ViewBuilder
    private var quarantineNoticeStrip: some View {
        let count = app.quarantinedCount
        if count > 0 {
            let copy = "\(count) Take\(count == 1 ? "" : "s") couldn't be verified and \(count == 1 ? "was" : "were") skipped."
            noticeStrip(
                icon: "lock.slash",
                text: copy,
                tint: Color.ckRuby,
                background: Color.ckRuby.opacity(0.12),
                accessibilityLabel: "quarantine notice",
                onDismiss: { app.clearQuarantineNotice() }
            )
        }
    }

    private var timeline: some View {
        // ScrollViewReader wraps the timeline so the Spotlight deep-link handler
        // (Task 6.19) can scroll programmatically to a target Take id.
        ScrollViewReader { proxy in
            ScrollView {
              // Zero-spacing wrapper: a ScrollView's implicit VStack would add ~8pt
              // between the offset reader and the list, pushing the first Take ~8pt
              // below the pinned Obie (owner 2026-06-16 — the visible "jump" on
              // designating an Obie). This makes them flush so positions match.
              VStack(spacing: 0) {
                // Track scroll offset to ghost month markers in/out.
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("dailies")).minY
                    )
                }
                .frame(height: 0)

                // Inter-card spacing is user-configurable (Compact/Standard/Comfort —
                // owner 2026-06-16). The chosen `gap` minus the 12pt each row already
                // carries gives the visible card-to-card distance, sized so a lower
                // card's Iris (straddling its top edge) never overlaps the card above.
                LazyVStack(alignment: .leading, spacing: interCardSpacing) {
                    // The Obie is no longer here — it's a STATIC pinned header now
                    // (owner 2026-06-16; see `heading`). The scrolling list below is
                    // the non-Obie Takes only, which scroll up and under the pinned Obie.

                    // Filter active but no non-Obie Take matches: quiet line in
                    // place of the grouped list (NOT the first-run empty state).
                    if !activeFilter.isEmpty && filteredTakes.isEmpty {
                        Text("Nothing here yet.")
                            .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                            .foregroundStyle(Color.ckTextSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                            .accessibilityIdentifier("timeline-filter-empty")
                            .accessibilityLabel("Nothing here yet.")
                    }

                    ForEach(Array(monthGroups.enumerated()), id: \.element.month) { groupIndex, group in
                        // Ghosted month marker — appears only while scrolling. The
                        // FIRST group's marker is suppressed (owner 2026-06-16): it
                        // reserved ~25pt of always-on height between the pinned Obie
                        // and the first row, inflating that gap well past the chosen
                        // Take spacing. Later groups keep their markers as section
                        // breaks; the topmost month reads from the DAILIES heading.
                        if groupIndex > 0 {
                            Text(group.month)
                                // .month — 11pt medium, 0.08em tracking (matches the
                                // DAILIES heading kerning; D-042, was 12pt untracked).
                                .font(CatchlightFont.ui(.medium, size: 11, relativeTo: .caption))
                                .kerning(0.88)
                                .foregroundStyle(Color.ckTextSecondary)
                                .padding(.leading, textColumnLeading)
                                .padding(.vertical, 6)
                                .opacity(scrolling ? 0.8 : 0)
                                .animation(.easeInOut(duration: 0.25), value: scrolling)
                                .accessibilityHidden(!scrolling)
                        }

                        ForEach(Array(group.takes.enumerated()), id: \.element.id) { takeIndex, take in
                            // The very first row across all months (when there's no Obie)
                            // anchors the Iris hint tooltip in Hint 2.
                            let isFirstOverall = (vm.obie == nil) && groupIndex == 0 && takeIndex == 0
                            let isNewRow = take.id == inlineNewTake?.id
                            row(for: take, isFirst: isFirstOverall)
                                .id(take.id)
                                // The in-place NEW Take blooms in — scale+fade from its
                                // Iris corner, driven by `newTakeBloom` (explicit, so it
                                // animates inside the LazyVStack and after the scroll).
                                // Existing rows are pinned at full (owner 2026-06-17).
                                // NB: the fade is FLOORED at 0.3, never 0 — SwiftUI maps
                                // opacity 0 to isHidden, and UIKit refuses
                                // becomeFirstResponder on a hidden view, so a 0-opacity
                                // bloom silently swallowed the new Take's keyboard/caret
                                // (you had to tap to focus). 0.3→1 still reads as a fade-in.
                                .scaleEffect(isNewRow ? 0.92 + 0.08 * newTakeBloom : 1, anchor: .topLeading)
                                .opacity(isNewRow ? (0.3 + 0.7 * newTakeBloom) : 1)
                        }
                    }
                }
                // Section 4 / D-041 — inset-aware on BOTH edges (the app runs
                // full-bleed, so these manual paddings are the only safe-area
                // correction). Top: clear the pinned heading + its 12pt fade on
                // large-inset devices (was a fixed 52 that ignored the inset, so
                // the first Take tucked under the fade on iPhone 17 / iOS 26.5.1).
                // Bottom: lift the last-row clearance by the home-indicator inset
                // so it still clears the now-raised dock.
                .padding(.top, timelineTopInset)
                // While editing, add a screenful of scroll room below the cards so the
                // focused Take can ALWAYS scroll up to its clear position above the
                // keyboard — otherwise the bottom-most Take (where new ones land under
                // Oldest-first) clamps against the content end and sits high, its top
                // tucked under the heading fade (owner 2026-06-19). Empty space below
                // the keyboard, so it's never visible; removed on exit.
                .padding(.bottom, CatchlightLayout.dockClearance + deviceBottomInset
                         + (ui.isEditingInPlace ? editScrollRoom : 0))
                .frame(maxWidth: .infinity, alignment: .leading)
                // FILTERING exit: tapping empty timeline background (not rows /
                // Irises — they stay fully interactive and win hit-testing)
                // returns the dock to RESTING and clears all filters. A
                // .background tap catcher (not an overlay) so row gestures and
                // scrolling are unaffected; attached only in FILTERING.
                .background {
                    if ui.isEditingInPlace {
                        // Tapping anywhere off the focused Take commits the edit
                        // (owner 2026-06-17 — "tap the masked area to save"). Masked
                        // rows commit via their own tap handlers; this catches the
                        // empty gaps so a single-Take timeline can still be exited.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { saveInlineEdit() }
                            .accessibilityLabel("Save and close")
                            .accessibilityHint("Double-tap to save this Take and stop editing.")
                    } else if ui.dockMode == .filtering {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { ui.exitToResting() }
                            .accessibilityLabel("Clear filters")
                            .accessibilityHint("Double-tap the timeline background to clear all filters.")
                    }
                }
              }   // VStack(spacing: 0)
            }
            .scrollIndicators(.hidden)   // the spine is the timeline affordance (owner 2026-06-16)
            // NOTE: deliberately NO `.scrollDismissesKeyboard` here — it interfered with
            // a NEW Take's keyboard appearing (the programmatic scroll-to-new-row
            // suppressed it). The keyboard is dismissed via the grabber bar on top of
            // the keyboard instead (BlockTextEditor.showsKeyboardGrabber, owner 2026-06-17).
            .coordinateSpace(name: "dailies")
            .onPreferenceChange(ScrollOffsetKey.self) { _ in markScrolling() }
            .onPreferenceChange(FirstRowTopKey.self) { firstRowTop = $0.isFinite ? $0 : nil }
            // `initial: true` (2026-06-10): when the Spotlight tap arrives from
            // another tab, this view is created with the target ALREADY set, so
            // a change-only observer never fired — no scroll, and the highlight
            // never cleared (blocking re-taps of the same result).
            .onChange(of: ui.spotlightTargetTakeID, initial: true) { _, newTarget in
                // Task 6.19 — Spotlight tap deep-link. Scroll the matching row
                // into view and let the row's own opacity flash do the rest.
                guard let id = newTarget else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(id, anchor: .center)
                }
                // Clear the target after the flash has time to start so a
                // subsequent tap on the same item re-triggers the highlight.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    if ui.spotlightTargetTakeID == id { ui.spotlightTargetTakeID = nil }
                }
            }
            // Edit-in-place Phase 2 — revealing a just-created Take takes TWO scrolls:
            // 1) INITIAL reveal (here): a new Take is created off-screen (bottom, under
            //    Oldest-first), so the LazyVStack hasn't built its row yet — it can't
            //    take focus or raise the keyboard until it's scrolled into view. This
            //    instantiates it. Does NOT clear the target — the final position is set
            //    on keyboardDidShow.
            .onChange(of: scrollToTakeID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.82))
                }
            }
            // 2) AUTHORITATIVE settle: on keyboard DID-show — AFTER the keyboard has
            //    shrunk the scroll viewport — scroll the focused Take to the low
            //    anchor. Measuring `0.82` against the REDUCED viewport lands the Take
            //    just above the keyboard EVERY time. Scrolling on willShow instead
            //    (against the still-animating, not-yet-shrunk viewport) made the rest
            //    position vary run-to-run / sit too low — owner 2026-06-19, reverting
            //    the 2026-06-18 "in sync" switch in favour of consistency. Guarded so
            //    a stale target can't scroll a later, unrelated edit.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                guard let id = scrollToTakeID else { return }
                guard id == ui.editingTakeID else { scrollToTakeID = nil; return }
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.82))
                }
                scrollToTakeID = nil
            }
        }
    }

    private func row(for take: Take, isFirst: Bool = false) -> some View {
        // Swipe actions (2026-06-16): swipe LEFT → Delete (all rows), swipe RIGHT →
        // Mark done (Tasks only — `complete` has no meaning on a plain Note). The
        // same mutations stay on the long-press context menu as the VoiceOver /
        // fallback path; this is the discoverable, iOS-native promotion of them.
        //
        // The action band spans from the card's leading edge to the SCREEN's
        // trailing edge: only `.leading` padding is on the wrapper, while the card's
        // 20pt right margin moves INSIDE the content. That lets the Delete fill flush
        // to the screen edge on a full swipe (was stopping 20pt short), while the
        // card looks identical at rest. `contentVerticalInset: 6` matches
        // TakeRowView's `.padding(.vertical, 6)` so the reveal mirrors the card's
        // height exactly (it already tracks the card's content-driven growth).
        SwipeActionRow(
            id: take.id,
            leading: take.isTask
                ? SwipeAction(
                    title: take.isComplete ? "Not done" : "Done",
                    systemImage: take.isComplete ? "arrow.uturn.left" : "checkmark",
                    tint: .ckEmber,            // Task accent — owner to confirm on device
                    style: .standard,
                    perform: {
                        guard app.ensureEntitled() else { return }
                        vm.toggleComplete(take)
                    }
                )
                : nil,
            trailing: SwipeAction(
                title: "Delete",
                systemImage: "trash",
                tint: .ckRuby,                 // HiFi alert red — owner to confirm on device
                style: .destructive,
                perform: {
                    guard app.ensureEntitled() else { return }
                    vm.delete(take)
                }
            ),
            openRowID: $openSwipeRowID,
            leadingInset: spineX - CatchlightLayout.cardSpineInset,
            trailingInset: 20,
            contentVerticalInset: 6
        ) { swipeOffset in
            // BOTH margins live inside the content so the wrapper spans the full
            // screen width — letting each action fill reach its screen edge. The
            // card's leading edge is `cardSpineInset` left of the spine (the card
            // covers the spine; the Iris nests in its corner). `swipeOffset` slides
            // the CARD only — TakeRowView keeps the Iris on the spine.
            rowContent(for: take, cardSwipeOffset: swipeOffset, isFirst: isFirst)
                .padding(.leading, spineX - CatchlightLayout.cardSpineInset)
                .padding(.trailing, 20)
        }
        .background(alignment: .top) {
            // The first row publishes its top Y (shared "dailies" space) so the
            // spine starts exactly at the first Iris — whether that's the pinned
            // Obie or a row sitting under an invisible month marker.
            if isFirst {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: FirstRowTopKey.self,
                        value: geo.frame(in: .named("dailies")).minY
                    )
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if isFirst && orientation.showIrisHint {
                OrientationTooltip(text: "Tap the Iris to shape this Take.", arrowEdge: .leading)
                    .fixedSize()
                    // Raise the bubble so its leading arrow — which sits at the
                    // bubble's vertical centre — lines up with the Iris centre
                    // rather than hanging below it (owner 2026-06-16). The Iris
                    // centre sits on the card's top edge, which is TakeRowView's
                    // own 6pt vertical pad below this overlay's top. Redefining
                    // the .top guide as `center − 6` lands the bubble's centre at
                    // y = 6 no matter how many lines it wraps to (height-independent).
                    .alignmentGuide(.top) { d in d[VerticalAlignment.center] - 6 }
                    .offset(x: spineX + CatchlightLayout.circleDiameter)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                    .allowsHitTesting(false)
            }
        }
        // Edit-in-place (owner 2026-06-17): mask every row except the one under
        // focus — the "Iris-touch focus" applied to editing. The timeline still
        // scrolls (the focused row scrolls with it); masked rows stay tappable so a
        // tap on one commits the edit (see `rowContent`'s tap handlers).
        .opacity(ui.isEditingInPlace && ui.editingTakeID != take.id ? 0.12 : 1)
    }

    // MARK: - Edit-in-place actions

    /// A non-optional binding into `editDraft` for the inline editor. The fallback
    /// `Take()` is never reached in practice — `beginInlineEdit` sets `editDraft`
    /// before `editingTakeID`, so the editor only renders once the draft exists.
    private var editDraftBinding: Binding<Take> {
        Binding(get: { editDraft ?? Take() }, set: { editDraft = $0 })
    }

    /// The applicable Angle's full-screen presentation, bound to the live `editDraft`.
    /// (Only the list Angle exists today; it applies whenever the draft has check items.)
    @ViewBuilder
    private var angleCover: some View {
        if let angle = AngleRegistry.applicable(to: editDraft ?? Take()).first {
            // Closing the Angle commits and EXITS the edit (owner 2026-06-19) —
            // otherwise it dropped back onto the keyboard-less focused Take (the
            // "dead screen"). The Angle's ticks rode the draft, so the save keeps them.
            angle.makePresentation(editDraftBinding) {
                anglePresented = false
                saveInlineEdit()
            }
        } else {
            Color.ckBackground.ignoresSafeArea().onAppear { anglePresented = false }
        }
    }

    /// Focus a Take for in-place editing: seed the draft (a blank Take gets one empty
    /// prose row to type into) and drop the caret at the END of the content — the
    /// "continue / append" position (owner 2026-06-17). The caret's block is the
    /// text-entry row, and iOS keyboard avoidance keeps THAT row above the keyboard —
    /// so focusing the LAST block pulls the bottom of the Take clear of the keyboard
    /// (the obscured-bottom fix), and lands you ready to keep writing. (`BlockTextEditor`
    /// places the caret at the end of the focused block's text on becoming first
    /// responder.)
    private func beginInlineEdit(_ take: Take) {
        // Task 6.20: editing is gated for lapsed users — paywall opens instead.
        guard app.ensureEntitled() else { return }
        var t = take
        if t.blocks.isEmpty { t.blocks = [.text(TextBlock(text: ""))] }
        editDraft = t
        editFocusedBlockID = t.blocks.last?.id
        ui.beginEditingInPlace(take)
        // Lift the Take above the keyboard via the same one-shot target the new-Take
        // and fan paths use (owner 2026-06-19). Previously an existing Take set no
        // target and leaned on iOS's native avoidance, which scrolled it up only a
        // little — "nowhere near enough" when it started below the keyboard line.
        scrollToTakeID = take.id
    }

    /// Create a NEW Take in place (Phase 2): seed the blank draft, inject it into the
    /// timeline at the Order-appropriate end (via `displayedTakes`), focus it, and
    /// scroll it into view (it may land off-screen at the bottom under Oldest-first).
    /// Not persisted until the inline save — a blank one dismissed leaves nothing.
    private func beginNewInlineEdit(_ take: Take) {
        var t = take
        if t.blocks.isEmpty { t.blocks = [.text(TextBlock(text: ""))] }
        editFocusedBlockID = t.blocks.first?.id
        // Mark this Take to be revealed once its keyboard is fully up (see the
        // keyboardDidShow handler). Scrolling AFTER the keyboard settles — against the
        // keyboard-reduced viewport — lands it at the same anchor every time, instead of
        // racing iOS keyboard avoidance (which made the rest position vary run-to-run:
        // nice / half-behind the keyboard / sliding up — owner 2026-06-18).
        scrollToTakeID = take.id
        // Insert the row COLLAPSED (bloom 0.3 → scale 0.92) as the rest masks back, then
        // bloom it in explicitly so the "appear" is visible wherever it lands (owner
        // 2026-06-17 — should feel organic; LazyVStack swallows insertion transitions).
        newTakeBloom = 0
        editDraft = t
        withAnimation(UIState.fanFade) { ui.editingTakeID = take.id }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { newTakeBloom = 1 }
        }
    }

    /// Commit the in-place edit through the same path the old editor used: drop empty
    /// prose rows, then either discard a never-saved blank Take or `vm.save`.
    private func saveInlineEdit() {
        editFocusedBlockID = nil            // release the keyboard first
        defer { editDraft = nil; ui.endEditingInPlace() }
        guard var t = editDraft else { return }
        guard app.ensureEntitled() else { return }
        t.removeEmptyTextBlocks()
        let isBlank = t.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !t.isTask && t.timeReminder == nil && !t.isObie
            && t.attachments.isEmpty && t.locationReminder == nil
        let storedCopy = try? vm.store.take(id: t.id)
        let storedHadContent = (storedCopy?.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        if isBlank && !storedHadContent {
            vm.discardIfPresent(t)
        } else {
            vm.save(t)
        }
    }

    /// Discard the edits (owner 2026-06-17 — via the row's long-press menu): drop the
    /// draft and leave the stored Take exactly as it was. A no-op revert, never a
    /// delete.
    private func discardInlineEdit() {
        editFocusedBlockID = nil
        editDraft = nil
        ui.endEditingInPlace()
    }

    /// Apply a Focus-ring selection to the inline draft. The draft is the single
    /// source of truth while editing, so the selection rides the inline save (fixing
    /// the Obie revert: the
    /// fan used to write the store, then the stale draft overwrote it). The Task Mark
    /// reshapes the live blocks; Note/Reminder are flags; Obie warns-then-defers when
    /// one already exists, mirroring the timeline long-press.
    private func applyInlineFanCommand(_ command: UIState.EditorFanCommand) {
        guard var d = editDraft else { return }
        d.isNote = command.isNote

        var newTaskEntryID: UUID?
        if command.isTask && !d.isTask {
            newTaskEntryID = d.convertToChecklist()
        } else if !command.isTask && d.isTask {
            d.convertToProse()
        }

        if command.hasReminder {
            let when = command.reminderDate
                ?? d.timeReminder?.scheduledDate
                ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            d.timeReminder = TimeReminder(scheduledDate: when,
                                          notificationIdentifier: d.id.uuidString,
                                          alarmEnabled: command.reminderAlarm,
                                          isAllDay: command.reminderAllDay)
        } else {
            d.timeReminder = nil
        }

        // Obie ON while another Obie exists → confirm first (the existing Obie is
        // demoted by the store's single-Obie upsert when this draft saves). Leave it
        // off until confirmed; otherwise apply the selection directly.
        if command.isObie && !d.isObie, let other = vm.obie, other.id != d.id {
            d.isObie = false
            pendingInlineObieConfirm = true
        } else {
            d.isObie = command.isObie
        }

        d.normaliseActivityFloor()
        editDraft = d

        // Restore the editor keyboard after the ring (and its reminder picker) — the
        // ring-open path cleared focus, so re-assert it here. A freshly-added task
        // entry takes the caret; otherwise the first block does.
        let refocus = newTaskEntryID ?? d.blocks.first?.id
        editFocusedBlockID = nil
        if let refocus {
            // Bring the Take above the rising keyboard (owner 2026-06-19): the ring
            // closed with the keyboard down, and re-focusing raises it again. Without
            // a scroll target the Take can sit under the keyboard — e.g. a new Take
            // just reshaped to a Task, sorted to the bottom under Oldest-first. Same
            // one-shot target the new-Take flow uses; the keyboardDidShow handler
            // settles it to the low anchor against the keyboard-reduced viewport.
            scrollToTakeID = d.id
            DispatchQueue.main.async { editFocusedBlockID = refocus }
        }
    }

    private func confirmInlineObie() {
        pendingInlineObieConfirm = false
        guard var d = editDraft else { return }
        d.isObie = true
        d.normaliseActivityFloor()
        editDraft = d
        orientation.didDismissObieIntro()
    }

    private func cancelInlineObie() {
        pendingInlineObieConfirm = false   // draft.isObie was left off
        orientation.didDismissObieIntro()
    }

    /// The row's visual content (Iris + card). `cardSwipeOffset` slides the card
    /// (only) for its swipe actions, supplied live by the enclosing `SwipeActionRow`.
    private func rowContent(for take: Take, cardSwipeOffset: CGFloat = 0, isFirst: Bool = false) -> some View {
        let isEditingThis = ui.editingTakeID == take.id
        let editingActive = ui.isEditingInPlace
        return TakeRowView(
            // While editing this row, the Iris reflects the LIVE draft (Obie ring,
            // reminder, task glyph update as you shape) — owner point 6, contextual
            // features stay live. Other rows render their stored state.
            take: isEditingThis ? (editDraft ?? take) : take,
            onTapCircle: { irisCentre in
                // While another Take is focused, any tap outside it commits and exits.
                if editingActive && !isEditingThis { saveInlineEdit(); return }
                // Hint 2 is dismissed by tapping any Iris.
                orientation.didTapIris()
                // Release the editor's keyboard BEFORE the Focus ring opens (owner
                // lockup 2026-06-18). Leaving the editor first-responder while the ring
                // + reminder picker sit on top made the keyboard fight the overlay —
                // Done re-raised it / needed a second tap. The ring owns the
                // interaction; the commit re-focuses (applyInlineFanCommand).
                if isEditingThis { editFocusedBlockID = nil }
                // Section 8 — bloom the fan in place at the tapped Iris (window
                // coords match the full-screen overlay space). The .zero fallback
                // (screen centre) only survives as a last resort. While editing THIS
                // Take, the fan opens against the live draft so it reflects unsaved
                // shaping, and its commit routes back to the draft (owner 2026-06-17).
                ui.openPetalFan(for: isEditingThis ? (editDraft ?? take) : take, origin: irisCentre)
            },
            onLongPressCircle: {
                // Iris long-press is disabled during editing (discard moved to the
                // Take's long-press menu — owner 2026-06-17); a press on a masked row
                // just commits and exits.
                if editingActive { if !isEditingThis { saveInlineEdit() }; return }
                // Hint 4: arm the Obie introduction tooltip on the first long-press.
                // The actual designation still proceeds — the tooltip provides
                // context "before the action takes effect" (and persists over the
                // confirmation alert when one Obie already exists).
                orientation.triggerObieIntro()
                // Task 6.20: Obie designation is a mutation — gate it.
                guard app.ensureEntitled() else { return }
                vm.designateObie(take, replaceExisting: false)
            },
            onTapText: {
                // Edit-in-place (2026-06-17): a Take is edited in position, not in a
                // top-anchored overlay. Tapping a masked row while editing commits.
                if editingActive {
                    if !isEditingThis { saveInlineEdit() }
                    return
                }
                beginInlineEdit(take)
            },
            // Delete / complete paths (2026-06-10). Previously `vm.delete` had
            // no UI caller at all and nothing ever set `isComplete` — rows could
            // only accumulate, and the strikethrough/"complete" rendering was
            // unreachable. The row exposes both via a context menu on its text
            // column (kept off the circle so the Obie long-press still wins).
            onToggleComplete: {
                // Unified "mark done" — Tasks AND reminders (2026-06-18). Settles the
                // whole Take (ticks items + flips reminder isDone) via setMarkedDone.
                // While editing, apply to the live draft so it rides the save; at
                // rest, toggle through the store.
                if isEditingThis {
                    guard var d = editDraft else { return }
                    d.setMarkedDone(!d.isMarkedDone)
                    editDraft = d
                    return
                }
                guard app.ensureEntitled() else { return }
                vm.toggleDone(take)
            },
            onSetImportant: {
                // Manual Important mark (owner 2026-06-19). While editing, ride the
                // draft so it persists on the inline save; at rest, toggle through
                // the store.
                if isEditingThis {
                    guard var d = editDraft else { return }
                    d.isImportant.toggle()
                    editDraft = d
                    return
                }
                guard app.ensureEntitled() else { return }
                var t = take
                t.isImportant.toggle()
                vm.save(t)
            },
            // Make Obie from the card long-press (owner 2026-06-19 accessibility
            // path). Resting rows only — designating mid-edit goes through the Focus
            // ring. Same designation path as the Iris long-press (warns on conflict).
            onMakeObie: isEditingThis ? nil : {
                guard app.ensureEntitled() else { return }
                vm.designateObie(take, replaceExisting: false)
            },
            onDelete: {
                guard app.ensureEntitled() else { return }
                // Delete while editing: drop the draft and leave editing — there's
                // nothing to save once the Take is gone.
                if isEditingThis {
                    let doomed = editDraft ?? take
                    editFocusedBlockID = nil
                    editDraft = nil
                    ui.endEditingInPlace()
                    // `discardIfPresent` deletes an existing Take but no-ops a NEW
                    // one that was never saved (Phase 2) — no spurious not-found error.
                    vm.discardIfPresent(doomed)
                    return
                }
                vm.delete(take)
            },
            onDiscard: isEditingThis ? { discardInlineEdit() } : nil,
            // The editing row's Iris is the shape control (tap = Focus ring), so it
            // carries the retired editor's "editor-shape" id for tests + semantics.
            irisIdentifier: isEditingThis ? "editor-shape" : "take-iris",
            cardSwipeOffset: cardSwipeOffset,
            editingCard: isEditingThis
                ? { AnyView(InlineTakeEditCard(
                    draft: editDraftBinding,
                    focusedBlockID: $editFocusedBlockID,
                    onOpenAngle: {
                        editFocusedBlockID = nil   // drop the keyboard before the cover
                        anglePresented = true
                    },
                    onCommit: { saveInlineEdit() })) }
                : nil
        )
        .background(
            // Task 6.19 — brief flash when this row is the Spotlight deep-link
            // target. Uses the ember accent at low opacity so it reads as a
            // gentle pulse, not a notification.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.ckEmber.opacity(ui.spotlightTargetTakeID == take.id ? 0.18 : 0))
                .animation(.easeInOut(duration: 0.4), value: ui.spotlightTargetTakeID)
        )
    }

    // MARK: - Live filter (dock redesign 2026-06-10)

    /// The filter the dock's current state describes (empty in RESTING).
    private var activeFilter: SequenceFilter { ui.activeTimelineFilter }

    /// The non-Obie Takes in the user's chosen order. The VM hands them back
    /// newest-first (deterministic, with an id tie-break); Oldest first is its exact
    /// reverse, so the tie-break stays stable. The Obie is pinned separately.
    private var orderedTakes: [Take] {
        takeSort == .oldestFirst ? Array(vm.takes.reversed()) : vm.takes
    }

    /// `orderedTakes` narrowed through the live dock filter. The Obie is pinned
    /// separately and never filtered.
    private var filteredTakes: [Take] {
        let filter = activeFilter
        guard !filter.isEmpty else { return orderedTakes }
        return orderedTakes.filter { filter.matches($0) }
    }

    /// The new Take being created IN PLACE (Phase 2), if any: it lives in `editDraft`
    /// but is NOT yet in the store/`vm.takes` (or the Obie). nil when editing an
    /// existing Take or not editing.
    private var inlineNewTake: Take? {
        guard let id = ui.editingTakeID, let draft = editDraft, draft.id == id else { return nil }
        let known = vm.takes.contains { $0.id == id } || vm.obie?.id == id
        return known ? nil : draft
    }

    /// `filteredTakes` plus the in-place new Take (if any) injected at the
    /// Order-appropriate end — bottom for Oldest-first, top for Newest-first (its
    /// `createdAt = now` would sort there anyway; placed explicitly since it isn't in
    /// `vm.takes`). Bypasses the dock filter so a just-created Take is always visible.
    private var displayedTakes: [Take] {
        guard let newTake = inlineNewTake else { return filteredTakes }
        return takeSort == .oldestFirst ? filteredTakes + [newTake] : [newTake] + filteredTakes
    }

    // MARK: - Month grouping

    private struct MonthGroup { let month: String; let takes: [Take] }

    /// Cached formatter — `DateFormatter` construction is expensive and this
    /// property is evaluated on every body pass (including the scroll-driven
    /// `scrolling` state toggles).
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private var monthGroups: [MonthGroup] {
        var order: [String] = []
        var map: [String: [Take]] = [:]
        for take in displayedTakes {
            let key = Self.monthFormatter.string(from: take.createdAt)
            if map[key] == nil { order.append(key); map[key] = [] }
            map[key]?.append(take)
        }
        return order.map { MonthGroup(month: $0, takes: map[$0] ?? []) }
    }

    // MARK: - Scroll ghosting

    private func markScrolling() {
        if !scrolling { scrolling = true }
        scrollHideWork?.cancel()
        let work = DispatchWorkItem { scrolling = false }
        scrollHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The first timeline row's top Y (in the "dailies" space) — drives where the spine
/// begins. Only the `isFirst` row publishes; `min` keeps the topmost if more than
/// one ever reports during a transition. `.infinity` default ⇒ "not measured yet".
private struct FirstRowTopKey: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

// MARK: - Rings-on-a-wire texture (static dotted spine overlay)

/// The static dotted line laid over the solid spine. A plain vertical line stroked
/// with a fixed dash pattern — no phase, no animation. It sits in the screen-fixed
/// spine layer behind the scrolling cards, so the rings glide past the fixed dots and
/// read as sliding over a marked wire. Brighter than the 35% solid base so the dots
/// read; tune tone/spacing on device.
private struct DottedSpine: View {
    /// Offsets the dash pattern so the dots stay screen-static even as the frame top
    /// is anchored to the (sometimes moving) top Take. See `dottedSpinePhase`.
    var dashPhase: CGFloat = 0

    var body: some View {
        SpineLine()
            .stroke(SpineDots.color, style: SpineDots.style(phase: dashPhase))
    }
}

/// A vertical line down the centre of its frame — the path the dotted overlay strokes.
/// Internal (not private) so the in-front-of-Iris crown overlay in `TakeRowView` can
/// stroke the same dotted pattern.
struct SpineLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

/// The wire's dot pattern — shared by the gutter overlay (`DottedSpine`) and the
/// in-front-of-Iris crown overlay (`TakeRowView`) so they read as one dotted wire.
enum SpineDots {
    // 1 on / 3 off (owner 2026-06-16): denser than the original 1/7 so the dotted
    // spine reads as a more robust, present wire.
    static let dash: [CGFloat] = [1, 3]
    static var color: Color { Color.ckAccent.opacity(0.9) }
    static func style(phase: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: CatchlightLayout.spineWidth, lineCap: .round, dash: dash, dashPhase: phase)
    }
}

#Preview("Dailies — Night (populated)") {
    let store = InMemoryTakeStore()
    for t in SeedTakes.make() { try? store.upsert(t) }
    let app = AppModel.preview(store: store, onboarded: true)
    return DailiesView()
        .environment(app)
        .environment(app.dailiesVM)
        .environment(app.ui)
        .environment(app.orientation)
        .environment(app.conflictQueue)
        .preferredColorScheme(.dark)
}

#Preview("Dailies — Daylight (populated)") {
    let store = InMemoryTakeStore()
    for t in SeedTakes.make() { try? store.upsert(t) }
    let app = AppModel.preview(store: store, onboarded: true)
    return DailiesView()
        .environment(app)
        .environment(app.dailiesVM)
        .environment(app.ui)
        .environment(app.orientation)
        .environment(app.conflictQueue)
        .preferredColorScheme(.light)
}

#Preview("Dailies — empty") {
    let app = AppModel.preview(store: InMemoryTakeStore(), onboarded: true)
    return DailiesView()
        .environment(app)
        .environment(app.dailiesVM)
        .environment(app.ui)
        .environment(app.orientation)
        .environment(app.conflictQueue)
        .preferredColorScheme(.dark)
}
