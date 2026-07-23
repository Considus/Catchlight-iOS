//
//  DailiesView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  The homepage timeline — the ONE surface (dock redesign 2026-06-10). A vertical
//  scroll of TakeRowViews threaded by a 2px spine aligned to each circle's centre.
//  The Obie (if any) is pinned at the top with a small gap before the regular
//  list — ALWAYS, even when it doesn't match the active filter. A persistent
//  month divider (label + hairline) separates Takes by creation month. First-launch
//  empty state is a single Fog line.
//
//  Live filtering (2026-06-10): the dock's FILTERING toggles and SEARCHING query
//  produce `ui.activeTimelineFilter`; the non-Obie rows are narrowed through
//  `SequenceFilter.matches` before month-grouping. When a filter is active but
//  nothing matches, a quiet "Nothing here yet." line replaces the grouped list.
//  In FILTERING, tapping empty timeline background (not rows/Irises) exits to
//  RESTING and clears all filters.
//
//  Focus-ring fan and edit surfaces are presented by the parent RootView via the shared
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

    /// Reads the user's timeline-density choice live. The inter-card stack
    /// spacing is the chosen clear gap MINUS the two 6pt row paddings each card
    /// already carries (`.padding(.vertical, 6)`), so the visible card-to-card gap
    /// equals `TakeSpacing.gap`.
    @AppStorage(SettingsViewModel.TakeSpacing.defaultsKey)
    private var takeSpacingRaw: String = SettingsViewModel.TakeSpacing.default.rawValue
    private var takeSpacing: SettingsViewModel.TakeSpacing {
        SettingsViewModel.TakeSpacing(rawValue: takeSpacingRaw) ?? .default
    }
    /// Stack spacing + the Obie gap. `gap − 12` because each row adds 6pt top
    /// and 6pt bottom of its own; the result is the extra space between cards.
    private var interCardSpacing: CGFloat { max(0, takeSpacing.gap - 12) }

    /// Timeline order (owner 2026-06-16). Default Oldest first: oldest at the top,
    /// newer Takes accrue below. The Obie stays pinned above the list regardless.
    @AppStorage(SettingsViewModel.TakeSort.defaultsKey)
    private var takeSortRaw: String = SettingsViewModel.TakeSort.default.rawValue
    private var takeSort: SettingsViewModel.TakeSort {
        SettingsViewModel.TakeSort(rawValue: takeSortRaw) ?? .default
    }

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
    // The spine now begins at `deviceTopInset` (up behind the heading, dissolving in
    // its fade — owner 2026-07-04), a per-device constant, so the dots are naturally
    // screen-static. Phase = the frame's top so a dot lands on the same global-Y grid
    // as the through-Iris wire (which phases off its own screen minY).
    private var dottedSpinePhase: CGFloat { deviceTopInset }
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
    /// DEBUG A/B: render the timeline with the new recycling UIKit `UICollectionView`
    /// (Pillar 2) instead of the SwiftUI `ScrollView`+`VStack`. Default off (old ships);
    /// toggled in Settings › Debug. Read-only for now — gestures + edit come on top.
    /// Drives the "Make this your Obie?" confirmation when the editing long-press menu's
    /// "Make Obie" is chosen while another Obie already exists (owner 2026-07-06). The same
    /// warning the timeline long-press uses, but targeting the draft — the existing Obie is
    /// demoted by the store's single-Obie upsert when this draft saves.
    @State private var pendingInlineObieConfirm = false
    /// Drives the reminder picker opened from the editor keyboard's slot-2 Reminder
    /// button (owner 2026-06-21) — edits the editing draft's reminder in place. The
    /// keyboard is dropped before it presents (the established overlay-vs-keyboard
    /// pattern, [[catchlight-edit-in-place]]).
    @State private var editingReminder = false
    /// The block to re-focus when the reminder picker closes — so editing returns to a
    /// clean keyboard-up state rather than a focus-desynced one (owner 2026-06-21 ghost
    /// toolbar). Captured when the picker opens.
    @State private var reminderReturnFocus: UUID?
    /// The repeating-reminder Take awaiting a Delete choice (owner 2026-06-21). Swiping
    /// Delete on a recurring reminder asks "this occurrence" vs "the whole series"
    /// rather than deleting outright; nil when no such prompt is up.
    @State private var pendingRecurringDelete: Take?
    /// Bloom progress (0→1) for the in-place NEW Take's "appear". Driven explicitly
    /// (scale+opacity on the row) rather than via a LazyVStack insertion transition,
    /// which doesn't animate reliably. 1 at rest so existing rows are unaffected.
    @State private var newTakeBloom: Double = 1
    /// Whether the full-screen Angle is presented over the in-place editor. INTERIM
    /// (2026-06-18) — the Angle's eventual entry point is the right-side selector ring;
    /// this keeps it reachable for review until that's built. Bound to the live
    /// `editDraft` so its ticks / reorders / deletes ride the inline save.
    @State private var anglePresented = false


    /// "Creation date" setting — the in-place editor shows the stamp for `.editor` and
    /// `.always` (both include the editing surface), matching `InlineTakeEditCard`.
    @AppStorage(SettingsViewModel.CreationStamp.defaultsKey)
    private var creationStampRaw: String = SettingsViewModel.CreationStamp.default.rawValue
    private var creationStamp: SettingsViewModel.CreationStamp {
        SettingsViewModel.CreationStamp(rawValue: creationStampRaw) ?? .default
    }

    /// The keyboard's top edge in screen coordinates (incl. its docked toolbar — the
    /// keyboard frame reports the inputAccessoryView too). `.greatestFiniteMagnitude`
    /// when the keyboard is down, so the caret pin below never fires at rest.
    @State private var keyboardTopY: CGFloat = .greatestFiniteMagnitude
    /// The spine container's actual bottom edge in SCREEN coords (captured live via a
    /// GeometryReader). Used to place the search-mode wire terminus on the × ring without
    /// assuming how SwiftUI sizes the container under the keyboard (2026-07-11).
    @State private var spineContainerBottomY: CGFloat = 0

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

    /// The NEW timeline's top inset. `timelineTopInset` is written for the OLD rows, which carry a
    /// flat 6pt top padding — but every UIKit cell carries a `cardGap/2` HALF-GAP on each edge (so
    /// two adjacent cards make a full `gap`). That means the FIRST cell already contributes
    /// `cardGap/2` above itself, stacking on the content inset and leaving the top Take sitting
    /// `cardGap/2 - 6` too low at the scroll origin (owner 2026-07-15). Subtract the difference so
    /// the first card lands exactly where the old timeline puts it.
    private var newTimelineTopInset: CGFloat {
        max(0, timelineTopInset + 6 - takeSpacing.gap / 2)
    }

    /// Distance from the SCREEN BOTTOM to the spine's bottom terminus.
    ///
    /// At rest the wire plugs into the TOP of the Add "+" ring: the ring's top sits
    /// `dockBottomPadding + minTouchTarget` above the device bottom inset (the resting
    /// terminus below). In SEARCH with the keyboard up, the "+" is gone — the search
    /// bar's × cancel ring rides the keyboard at the SAME x (KeyboardSearchBar lays its
    /// grid so × lands exactly where + sits at rest). Left alone, the wire kept
    /// subtracting the resting-dock allowance and ended ~80pt ABOVE the raised bar,
    /// reading as "disconnected" (owner 2026-07-10). So while the search bar is on the
    /// keyboard we re-anchor the terminus to the TOP OUTER EDGE of that × ring instead.
    ///
    /// `keyboardTopY` is the keyboard's top edge in screen coords and INCLUDES the
    /// docked search bar (its inputAccessoryView) — so it IS the bar's top. The × ring
    /// sits `searchBarTopPad` below that (SearchBarAccessory: 10 top + 44 circle + 8),
    /// so the ring's top is `keyboardTopY + searchBarTopPad` from the screen top, i.e.
    /// `screenHeight - keyboardTopY - searchBarTopPad` up from the bottom. `max(resting…)`
    /// keeps it from ever terminating BELOW the resting position, and the guard falls
    /// back to resting the instant the bar isn't on the keyboard (keyboard lowered →
    /// `keyboardTopY` resets to the screen height).
    private var spineBottomInset: CGFloat {
        let resting = deviceBottomInset
            + CatchlightLayout.dockBottomPadding
            + CatchlightLayout.minTouchTarget
        guard ui.dockMode == .searching, ui.searchKeyboardUp,
              keyboardTopY < UIScreen.main.bounds.height,
              spineContainerBottomY > 0 else { return resting }
        // Place the wire's bottom on the × cancel ring's top edge. `keyboardTopY` (incl. the
        // docked search bar) IS the bar's top; the ring sits `ringTopOffset` below it. The
        // inset is measured from the spine container's ACTUAL bottom edge
        // (`spineContainerBottomY`, captured live), so it self-corrects to however SwiftUI
        // sizes the container under the keyboard — no assumptions about screen/keyboard math
        // (the source of the earlier "no change" miss). `ringTopOffset` is the only tunable;
        // calibrated in-sim 2026-07-11, owner may nudge on device.
        // = SearchBarAccessory.topPad: on the real keyboard `keyboardTopY` is the accessory's
        // true top, so the × ring's top outer edge sits exactly `topPad` below it (device-
        // calibrated 2026-07-11; the sim's no-keyboard quirk wanted a larger value).
        let ringTopOffset: CGFloat = 10
        return spineContainerBottomY - (keyboardTopY + ringTopOffset)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.ckBackground.ignoresSafeArea()
                // Track the keyboard top here (always present) — the old `timeline`'s copy
                // lives inside its ScrollView, which the NEW timeline doesn't render, so
                // `keyboardTopY` stayed off and the new-Take card collapsed to the very bottom
                // under the keyboard (invisible, 2026-07-14). This keeps it fed on BOTH timelines.
                .onReceive(NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                    guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                    else { return }
                    keyboardTopY = frame.origin.y
                }

            // Full-container probe (NO padding) → the spine container's true bottom edge in
            // screen coords, so the search-mode wire terminus can anchor to it without any
            // screen/keyboard assumptions. Kept separate from the padded spine so its
            // padding can't feed back into the measurement (2026-07-11).
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(GeometryReader { g in
                    Color.clear.preference(key: SpineContainerBottomKey.self,
                                           value: g.frame(in: .global).maxY)
                })
                .onPreferenceChange(SpineContainerBottomKey.self) { spineContainerBottomY = $0 }
                .allowsHitTesting(false)

            // The spine: a hairline behind the rows, at the circle centre. It
            // STARTS at the first Iris's top edge (HiFi §1 "the spine terminates at
            // the first Take") rather than the screen top — a full-height line poked
            // up into the gap below the DAILIES heading. First Iris centre = the
            // timeline's top content pad (deviceTopInset + headingClearance) + the
            // row's 6pt vertical pad; the top edge is one Iris radius higher. The
            // bottom runs on toward the Add button, covered by the dock fade (HiFi).
            // Owner 2026-06-16: the spine takes the dock buttons' ring colour
            // (Ember @ 35% — `dockRing()` in BottomDockView) so the wire and the
            // toolbar read as one family. Single-sourced via `ckSpineWire` so the
            // gutter spine and the through-Iris segments (TakeRowView, "rings on a
            // wire") never drift. Strokes `SpineLine` so it draws the same THREE
            // tracks as the dotted overlay (owner 2026-07-04).
            SpineLine()
                .stroke(Color.ckSpineWire, lineWidth: CatchlightLayout.spineWidth)
                // Fully hidden while editing in place (owner 2026-06-17): a thin line
                // reads as a "remnant" even at the 0.12 row-mask — especially once the
                // Obie card (which used to cover it) goes invisible, exposing the spine
                // at the empty Obie position. The faint masked CARDS carry the
                // "part of the timeline" feel; the connecting wire isn't needed in focus.
                .opacity(ui.isEditingInPlace ? 0 : 1)
                .frame(width: CatchlightLayout.spineWidth)
                .frame(maxHeight: .infinity)
                // Start up behind the heading so the wire always dissolves into the
                // top fade rather than beginning at the first Iris (owner 2026-07-04).
                .padding(.top, deviceTopInset)
                // Terminate the spine at the TOP EDGE of the Add button's ring rather
                // than running full-bleed under the dock (owner 2026-06-16: it was
                // visible through the +'s hollow ring). At rest the ring's top sits
                // `dockBottomPadding + minTouchTarget` above the device bottom inset so
                // the wire plugs into the top of the +; in search-with-keyboard it
                // re-anchors to the raised × ring instead (see `spineBottomInset`).
                .padding(.bottom, spineBottomInset)
                // Ride the terminus up/down WITH the keyboard, at the same gentle pace
                // the new-Take card uses, so the wire glides onto the search bar rather
                // than snapping (owner 2026-07-10).
                .animation(.easeOut(duration: 0.56), value: keyboardTopY)
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
                // Same top as the solid spine — up into the heading fade (owner 2026-07-04).
                .padding(.top, deviceTopInset)
                // Same bottom terminus + keyboard-follow as the solid spine.
                .padding(.bottom, spineBottomInset)
                .animation(.easeOut(duration: 0.56), value: keyboardTopY)
                .offset(x: spineX - CatchlightLayout.spineWidth / 2)
                .accessibilityHidden(true)

            // A first-launch-empty store shows the Fog line; but when a dock
            // filter is active the timeline (with its own filter-empty line)
            // always wins, so the background-tap exit remains available.
            if vm.isEmpty && activeFilter.isEmpty && inlineNewTake == nil {
                // A restore lands empty with the real Takes still in the cloud folder,
                // but that guidance is a full screen (RestoreFolderView, shown by RootView
                // while `restoreAwaitingFolder`), not an overlay here (owner 2026-07-02).
                emptyState
            } else {
                timeline
            }

            // New-Take editor, anchored above the keyboard (owner 2026-06-22): it rises
            // with the keyboard as the veil falls, instead of being chased to a far
            // (often off-screen) sorted row. Placed under the heading so a tall card
            // dissolves beneath it like a timeline card. On save it drops into its
            // sorted place; existing-Take editing is unchanged.
            // Save catcher for the in-place editor, BOTH new-Take AND existing-Take edits
            // (M5a consistency pass, 2026-07-15). The timeline is faded + non-interactive while
            // editing, so a tap off the card lands here and commits (tap-away-to-save). Before
            // the card below, so the card stays editable above it.
            if ui.isEditingInPlace {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { saveInlineEdit() }
            }

            // BOTH new-Take and existing-Take edits ride the SAME bottom-anchored `TakeEditCard`
            // that grows UP from the dockbar (owner consistency pass 2026-07-15), drawn BELOW the
            // heading so its top dissolves under the heading fade and its bottom always sits above
            // the dockbar (the top-anchored editPanel ran its bottom off-screen under the keyboard
            // — "the edit-Take card has no bottom").
            if ui.isEditingInPlace {
                newTakeBlockCard
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

            // (Existing-Take edit-in-place rides the bottom-anchored card above — BELOW the
            // heading — as the M5a consistency pass. The top-anchored `newTimelineEditOverlay` /
            // `editPanel` path it replaced was deleted at M5b, along with this view's copy of the
            // card: it now lives in the shared `TakeEditCard`.)

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
            // Opt-in auto-cleanup sweep on open (owner 2026-06-19): delete finished,
            // note-free Takes past the user's chosen retention window. No-op unless the
            // user turned it on (Settings default = Never); see DailiesViewModel.
            vm.runAutoCleanup(olderThan: SettingsViewModel.AutoCleanup.current.maxAge)
            // Trim the diagnostics log on the SAME sweep (owner 2026-07-16): reuse the retention
            // intent already expressed rather than add a setting for a log they never see. The log
            // takes the SHORTER of its own 30-day ceiling and this window — Auto-delete alone can't
            // govern it (it defaults to Never, which would leave the log unbounded in time, and
            // "keep my writing forever" isn't a wish to hoard technical logs).
            DiagnosticsLog.shared.enforceRetention(
                autoDeleteWindow: SettingsViewModel.AutoCleanup.current.maxAge)
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
        // Inline Obie confirmation (owner 2026-06-17; re-homed to the editing long-press
        // menu 2026-07-06) — mirrors the timeline long-press warning, but targets the
        // draft (the existing Obie is demoted by the store on save).
        .alert("Make this your Obie?", isPresented: $pendingInlineObieConfirm) {
            Button("Make Obie") { confirmInlineObie() }
            Button("Cancel", role: .cancel) { cancelInlineObie() }
        } message: {
            Text("Your existing Obie returns to the timeline — only one Take can be your Obie.")
        }
        // Recurring-reminder Delete (owner 2026-06-21): this occurrence vs the series.
        // "This occurrence" rolls the reminder forward (series + alarm stay live);
        // "Delete series" removes the whole Take like a normal delete.
        .confirmationDialog(
            "This is a repeating reminder.",
            isPresented: Binding(get: { pendingRecurringDelete != nil },
                                 set: { if !$0 { pendingRecurringDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete This Occurrence") {
                if let t = pendingRecurringDelete {
                    // Exit the editor first if this Take is being edited — otherwise a
                    // later save of the stale draft would overwrite (undo) the advance.
                    if ui.editingTakeID == t.id { discardInlineEdit() }
                    vm.advanceRecurring(t)
                }
                pendingRecurringDelete = nil
            }
            Button("Delete Series", role: .destructive) {
                if let t = pendingRecurringDelete { deleteTake(t) }
                pendingRecurringDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingRecurringDelete = nil }
        } message: {
            Text("Delete only the next occurrence, or the whole repeating series?")
        }
        // Interim Angle entry (2026-06-18): the full-screen list Angle, opened from the
        // editor's top-right affordance, bound to the live draft so ticks / reorders /
        // deletes ride the inline save. (Final entry point will be the selector ring.)
        .fullScreenCover(isPresented: $anglePresented) {
            angleCover
        }
        // Reminder editor from the keyboard's slot-2 button (owner 2026-06-21): edit a
        // reminder Take's time/cadence, or add one to a note, in place — the same picker
        // the Focus ring uses, applied straight to the editing draft.
        .sheet(isPresented: $editingReminder) {
            reminderEditorSheet
        }
    }

    /// The in-editor reminder picker, seeded from the draft's current reminder (or the
    /// user's default timing when adding one). Save writes the draft's `timeReminder`;
    /// Cancel leaves it untouched (we only mutate on Save, so both paths are safe).
    @ViewBuilder
    private var reminderEditorSheet: some View {
        let existing = editDraft?.timeReminder
        ReminderPickerSheet(
            initialDate: existing?.scheduledDate ?? FocusRingFanView.defaultReminderDate,
            initialAlarm: existing?.alarmEnabled ?? true,
            initialAllDay: existing?.isAllDay ?? false,
            initialRecurrence: existing?.recurrence ?? .none,
            initialWeekdays: existing?.weekdays ?? [],
            initialLocation: editDraft?.locationReminder,
            onSave: { date, alarm, allDay, recurrence, weekdays, location in
                if var d = editDraft {
                    // Either/or (owner 2026-06-24): location takes precedence and clears the
                    // time; otherwise the time "when" applies.
                    if let location {
                        d.locationReminder = location
                        d.timeReminder = nil
                    } else {
                        d.locationReminder = nil
                        d.timeReminder = TimeReminder(
                            scheduledDate: date,
                            notificationIdentifier: d.id.uuidString,
                            alarmEnabled: alarm,
                            isAllDay: allDay,
                            recurrence: recurrence,
                            weekdays: recurrence == .weekly ? weekdays : [])
                    }
                    d.normaliseActivityFloor()
                    editDraft = d
                }
                closeReminderEditor()
            },
            onCancel: { closeReminderEditor() }
        )
    }

    /// Open the reminder editor for the focused draft: remember the focused block, drop
    /// the keyboard (the proven overlay-vs-keyboard ordering — owner lockup 2026-06-18),
    /// then present.
    private func presentReminderEditor() {
        reminderReturnFocus = editFocusedBlockID
        editFocusedBlockID = nil
        editingReminder = true
    }

    /// Dismiss the reminder editor and restore the editor's focus, so the keyboard
    /// returns and the editing state isn't left focus-desynced (owner 2026-06-21).
    private func closeReminderEditor() {
        editingReminder = false
        editFocusedBlockID = reminderReturnFocus
        reminderReturnFocus = nil
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
            // The title crossfades on a dock-mode change (DAILIES → SEQUENCE → SEARCH), and the
            // ZStack is what keeps the MASK out of that crossfade. Without it the
            // `.background(Color.ckBackground)` below was applied to the very view carrying
            // `.id` + `.transition`, so the mask faded WITH the title — and two half-faded opaque
            // layers don't compose to opaque. For ~150ms the mask went see-through and whatever
            // sits behind it showed: the spine wire above the Obie, or a Take scrolled up under
            // the top (owner 2026-07-16; measured off a screen recording — the wire region dipped
            // to 195 luma mid-fade and returned).
            //
            // The ZStack has a stable identity, so only the Text inside it transitions; the mask
            // is a sibling that never fades. Keep it that way: anything that must stay opaque
            // during the title change belongs OUTSIDE the `.id`/`.transition` view.
            ZStack {
                Text(headingTitle)
                    // Shared page-heading style (Cormorant ROMAN 24, kerned, centred —
                    // §catalogue, includes the kerning-centring fix).
                    .pageHeadingStyle()
                    // Recede the title while editing in place; the mask stays opaque so
                    // scrolled-up content still dissolves under the top.
                    .opacity(ui.isEditingInPlace ? 0.12 : 1)
                    .id(headingTitle)
                    .transition(.opacity)
            }
            .padding(.top, deviceTopInset + 14)
            .padding(.bottom, 2)
            .background(Color.ckBackground)
            if vm.obie != nil && !ui.isEditingInPlace {
                // With a pinned Obie: SOLID right down to the Obie's card top (no fade
                // — the gradient is semi-transparent and lets a scrolling Take peek).
                // The opaque Obie card continues the mask below. Its own Iris is drawn
                // ON TOP of the heading, so this doesn't cover it (owner 2026-06-16).
                // (A 12pt fade was tried here 2026-07-04 to run the spine into the top
                // fade with an Obie, but it let a Take peek above the Obie — reverted.)
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
        // The mask zone ABSORBS taps and reads as timeline background (owner 2026-07-16). It was
        // `.allowsHitTesting(false)`, so a tap here fell through to whatever Take had scrolled up
        // UNDER the mask — selecting a card the user couldn't see. Now it's a way out instead:
        // exit a Sequence, or commit an open edit. That last part matters — the tap used to reach
        // the save-catcher below, and absorbing it here must not lose that (hence the shared
        // `timelineBackgroundTap`).
        //
        // The pinned Obie is drawn AFTER the heading in the ZStack, so it still owns its hit
        // region and keeps its taps + swipe, including where this frame extends down behind it.
        //
        // The mask leaking mid-crossfade (a Take, then the spine wire, flashing through) was NOT
        // this gesture — it was the title's `.background` riding the `.transition`, fixed with the
        // ZStack above and measured off a screen recording.
        .contentShape(Rectangle())
        .onTapGesture { timelineBackgroundTap() }
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(headingTitle.capitalized)
    }

    /// The PINNED Obie (owner 2026-06-16) — a static element sitting at the SAME
    /// position a plain first Take would (`deviceTopInset + headingClearance`), so the
    /// top item is in the same place with or without an Obie. Scrolling Takes pass
    /// behind its solid background and dissolve under the fade below it. It keeps its
    /// swipe actions, so it stays interactive (the heading title/fade above do not).
    /// Whether the pinned Obie slot yields while an edit is open — ALWAYS, now. For another Take
    /// it would ghost over the faded timeline; for the Obie ITSELF the floating card is the editor,
    /// so a visible pinned slot is a duplicate (two live editors on one draft, device 2026-07-16).
    private func pinnedObieStandsDown(_ obie: Take) -> Bool { ui.isEditingInPlace }

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
                //
                // OLD timeline: when the Obie ITSELF is the focused Take it stays bright and
                // interactive — the pinned slot IS its inline editor (owner-agreed re-engineer
                // 2026-06-19, back to in-place editing).
                // NEW timeline: the floating card is the editor for EVERY Take, so the pinned slot
                // must stand down for its own Take too — otherwise the read card sits at the top
                // while the editor floats below it: the SAME Obie twice (device 2026-07-16).
                .opacity(pinnedObieStandsDown(obie) ? 0 : 1)
                .allowsHitTesting(!pinnedObieStandsDown(obie))
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
        // Dodge the status bar / Dynamic Island (owner 2026-06-27). The app root is
        // full-bleed (`.ignoresSafeArea(.container)`), so this `.safeAreaInset(.top)`
        // has no top safe area to sit below and lands the strips UNDER the island, where
        // a sync/conflict/error notice is clipped and unreadable. Pad down by the same
        // `deviceTopInset` the heading uses to clear the bar — but ONLY when a strip is
        // actually showing, so an empty stack reserves no height and the timeline isn't
        // pushed down at rest.
        .padding(.top, hasTopStrip ? deviceTopInset : 0)
    }

    /// Whether ANY top notice strip is currently visible — gates the status-bar dodge
    /// above so the inset reserves space only when there's something to show. Mirrors the
    /// individual strips' own visibility conditions (conflict / lapse / storage / sync /
    /// quarantine); keep in sync if a strip's trigger changes.
    private var hasTopStrip: Bool {
        conflicts.pending.count > 0
            || app.subscriptionStatus == .lapsed
            || vm.lastError != nil
            || app.lastSyncError != nil
            || app.quarantinedCount > 0
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

    /// THE timeline (Pillar 2, default since M7): the recycling UIKit collection, fed the real
    /// month groups, spine column, density gap, and heading/dock insets. The pinned Obie, heading,
    /// and gutter spine still come from the surrounding body.
    private var timeline: some View {
        UIKitTimeline(
            groups: monthGroups.map { TimelineMonthGroup(id: $0.key, title: $0.month, takes: $0.takes) },
            spineX: spineX,
            cardGap: takeSpacing.gap,
            activeMonthKey: ui.filterMonth,
            onToggleMonthFilter: { key in
                withAnimation(.easeInOut(duration: 0.2)) { ui.toggleMonthFilter(key) }
            },
            // Snoozed overdue Takes read "SNOOZED" rather than "OVERDUE" in the label lane
            // (D-058/D-060). Not derivable from the Take, so it has to be handed over.
            snoozedIDs: vm.snoozedReminderIDs,
            topInset: newTimelineTopInset,
            bottomInset: CatchlightLayout.dockClearance + deviceBottomInset,
            onToggleDone: { take in
                guard app.ensureEntitled() else { return }
                vm.toggleDone(take)
            },
            onDelete: { take in
                guard app.ensureEntitled() else { return }
                if take.timeReminder?.repeats == true { pendingRecurringDelete = take }
                else { deleteTake(take) }
            },
            // Iris tap → bloom the Focus-ring fan at the tapped Iris (window coords
            // match RootView's full-screen overlay). No edit-in-place on the new
            // timeline yet (M4), so the SwiftUI row's editing branches don't apply.
            onTapCircle: { take, irisCentre in
                orientation.didTapIris()
                ui.openFocusRingFan(for: take, origin: irisCentre)
            },
            // Iris long-press toggles Obie (owner 2026-07-04): demote is not gated,
            // designate is. Mirrors DailiesView.rowContent's onLongPressCircle.
            onLongPressCircle: { take in
                if take.isObie { vm.demoteObie(take); return }
                orientation.triggerObieIntro()
                guard app.ensureEntitled() else { return }
                vm.designateObie(take, replaceExisting: false)
            },
            // Card context-menu extras (resting-row set) — mirror rowContent. Mark-done
            // and Delete reuse onToggleDone/onDelete above.
            onSetImportant: { take in
                guard app.ensureEntitled() else { return }
                var t = take
                t.isImportant.toggle()
                vm.save(t)
            },
            onMakeObie: { take in
                guard app.ensureEntitled() else { return }
                vm.designateObie(take, replaceExisting: false)
            },
            onExport: { take in
                ExportCoordinator.presentShareSheet(takes: [take])
            },
            // M4.1 — tap a card begins edit-in-place, or commits an open edit when tapping
            // a DIFFERENT Take (mirrors rowContent.onTapText). New-Take is unaffected here;
            // it rides the keyboard-anchored `newTakeBlockCard` overlay.
            onTapText: { take in
                if ui.isEditingInPlace {
                    if ui.editingTakeID != take.id { saveInlineEdit() }
                    return
                }
                beginInlineEdit(take)
            },
            onTapBackground: { timelineBackgroundTap() },
            // M4.6 — fade + disable the collection while editing (cards recede, taps fall
            // through to the save catcher). Covers both existing-edit and new-Take.
            isEditing: ui.isEditingInPlace
        )
    }

    /// The editing card for the new timeline. A NEW Take and an existing-Take edit are the
    /// SAME card (the M5a consistency pass, owner 2026-07-15 — a top-anchored editor ran its
    /// bottom off-screen under the keyboard, "the edit-Take card has no bottom").
    ///
    /// Everything about it — the keyboard anchoring, the caret descent, the downward drop, the
    /// grow-up and the cap — now lives in the shared `TakeEditCard`, which the Storyboard uses
    /// too (M5b, 2026-07-16), so the owner-tuned geometry has ONE home and cannot drift between
    /// the two screens. The old top-anchored `newTimelineEditOverlay` / `editPanel` path that
    /// the consistency pass retired is deleted with it.
    /// A tap on the timeline BACKGROUND — every part of the screen that isn't a Take. Three
    /// callers: the collection's empty space, a month divider's blank strip, and the heading
    /// mask zone. One home so they can't drift apart (they read as one surface to the user).
    ///
    /// The editing branch is what the heading needs: while editing, the mask zone used to fall
    /// through to the save-catcher, and the heading absorbing taps must not lose that. The
    /// collection never reaches that branch (the catcher sits above it), which is harmless.
    private func timelineBackgroundTap() {
        if ui.isEditingInPlace { saveInlineEdit(); return }
        if ui.dockMode == .filtering || ui.dockMode == .searching { ui.exitToResting() }
    }

    private var newTakeBlockCard: some View {
        KeyboardTakeEditor(
            draft: editDraftBinding,
            focusedBlockID: $editFocusedBlockID,
            leadingInset: spineX - CatchlightLayout.cardSpineInset,
            onOpenAngle: { editFocusedBlockID = nil; anglePresented = true },
            onEditReminder: { presentReminderEditor() },
            onDiscard: { discardInlineEdit() },
            // Iris tap → the Focus-ring fan, against the LIVE DRAFT so it reflects unsaved
            // shaping and its commit routes back through the draft rather than the store
            // (owner 2026-06-17; `RootView` keys that off `ui.editingTakeID`). Drop the keyboard
            // first, exactly as the old timeline's row does before blooming the fan.
            onTapIris: { irisCentre in
                editFocusedBlockID = nil
                // No spotlight card — this IS the editor (owner 2026-07-16). The fan still blooms
                // at the Iris; it just doesn't redraw the Take as a read card over the veil.
                ui.openFocusRingFan(for: editDraft ?? Take(), origin: irisCentre, showsCard: false)
            }
        )
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
            // Done is offered for any settle-able Take — a Task OR a reminder (owner
            // 2026-06-21). Previously Task-only, so an overdue/future reminder had no
            // swipe-Done at all. Routes through `toggleDone` (the whole-Take settle the
            // long-press menu uses), so a reminder's `isDone` flips: the card greys and
            // an overdue reminder clears its ruby. `isMarkedDone` (not `isComplete`)
            // drives the label so a reminder reads correctly.
            leading: take.canBeMarkedDone
                ? SwipeAction(
                    title: take.isMarkedDone ? "Not done" : "Done",
                    systemImage: take.isMarkedDone ? "arrow.uturn.left" : "checkmark",
                    tint: .ckEmber,            // Task accent — owner to confirm on device
                    style: .standard,
                    perform: {
                        guard app.ensureEntitled() else { return }
                        vm.toggleDone(take)
                    }
                )
                : nil,
            trailing: SwipeAction(
                title: "Delete",
                systemImage: "trash",
                tint: .ckRuby,                 // HiFi alert red — owner to confirm on device
                // A repeating reminder asks "this occurrence vs the series" first, so it
                // must NOT fly off on swipe (the row stays if "this occurrence" wins) —
                // `.standard` triggers the dialog; a normal Take keeps the destructive
                // slide-off (owner 2026-06-21).
                style: take.timeReminder?.repeats == true ? .standard : .destructive,
                perform: {
                    guard app.ensureEntitled() else { return }
                    if take.timeReminder?.repeats == true {
                        pendingRecurringDelete = take
                    } else {
                        deleteTake(take)
                    }
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
    /// The draft binding handed to the editor. The setter is GUARDED on the draft still existing:
    /// `BlockEditor` is UIKit-backed and its coordinator OUTLIVES the SwiftUI teardown, so a late
    /// write arriving after `saveInlineEdit`/`discardInlineEdit` cleared the draft would RESURRECT
    /// it through this setter and re-open the editor on an already-saved Take. The same shape (an
    /// unguarded binding into a long-lived UIKit coordinator) crashed `LockedCaptureView` on
    /// device, 2026-07-16. Safe because every begin-edit path assigns `editDraft` DIRECTLY —
    /// nothing starts an edit through this setter.
    private var editDraftBinding: Binding<Take> {
        Binding(get: { editDraft ?? Take() },
                set: { if editDraft != nil { editDraft = $0 } })
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
            // The draft stopped being a task mid-Angle (last check item deleted),
            // so no Angle applies. Route through the normal COMMIT (2026-07-01)
            // instead of just dropping the cover — the raw flag flip stranded the
            // user on a masked, keyboard-less editor, bypassing the blank check
            // until a mask tap later saved the emptied draft as a blank Note.
            Color.ckBackground.ignoresSafeArea().onAppear {
                anglePresented = false
                saveInlineEdit()
            }
        }
    }

    /// Focus a Take for in-place editing: seed the draft (a blank Take gets one empty
    /// prose row to type into) and drop the caret at the END of the content — the
    /// "continue / append" position (owner 2026-06-17). The caret's block is the
    /// text-entry row, and iOS keyboard avoidance keeps THAT row above the keyboard —
    /// so focusing the LAST block pulls the bottom of the Take clear of the keyboard
    /// (the obscured-bottom fix), and lands you ready to keep writing. (The editor's text view
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
    }

    /// Create a NEW Take in place (Phase 2): seed the blank draft, inject it into the
    /// timeline at the Order-appropriate end (via `displayedTakes`), focus it, and
    /// scroll it into view (it may land off-screen at the bottom under Oldest-first).
    /// Not persisted until the inline save — a blank one dismissed leaves nothing.
    private func beginNewInlineEdit(_ take: Take) {
        var t = take
        if t.blocks.isEmpty { t.blocks = [.text(TextBlock(text: ""))] }
        editFocusedBlockID = t.blocks.first?.id
        // NO reveal scroll for a new Take (owner 2026-06-22): when the timeline was scrolled
        // to the far end from where the new Take inserts (e.g. top, under Oldest-first → the
        // new Take lands at the bottom), the long-distance reveal left a blank screen. It
        // needs none now — the editor rides the keyboard as its own card, wherever the row
        // ends up. (The caret-pin this once leaned on died with the old timeline at M7.)
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
        t.removeEmptyTextBlocks()
        let isBlank = t.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !t.isTask && t.timeReminder == nil && !t.isObie
            && t.attachments.isEmpty && t.locationReminder == nil
        let storedCopy = try? vm.store.take(id: t.id)
        let storedHadContent = (storedCopy?.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        if isBlank && !storedHadContent {
            vm.discardIfPresent(t)          // nothing typed — no entitlement needed to discard
        } else if app.ensureEntitled() {
            vm.save(t)
        } else {
            // Paywall interrupted the save (owner 2026-07-01): hold the typed
            // draft for the paywall's outcome — saved on subscribe, dropped on
            // unsubscribed dismiss — never silently destroyed here. (Previously
            // the defer cleared the draft while the entitlement guard returned.)
            app.holdDraftForPaywall(t)
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

    /// Delete a Take from ANY entry point (swipe, context menu, recurring "Delete series"),
    /// exiting the in-place editor FIRST when the deleted Take is the one being edited
    /// (owner 2026-06-21). Without this, deleting the focused Take left `isEditingInPlace`
    /// true — a masked "dead" screen with no card, keyboard, or controls — and a tap on the
    /// mask ran `saveInlineEdit`, which would `vm.save` the still-set draft and RESURRECT
    /// the Take. The single rule: a Take action must never strand the user on the edit mask.
    private func deleteTake(_ take: Take) {
        if ui.editingTakeID == take.id {
            let doomed = editDraft ?? take
            editFocusedBlockID = nil
            editDraft = nil
            ui.endEditingInPlace()
            // `discardIfPresent` deletes an existing Take but no-ops a NEW one never saved
            // (Phase 2) — no spurious not-found error if the editor held an unsaved Take.
            vm.discardIfPresent(doomed)
            return
        }
        vm.delete(take)
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

        // Either/or (owner 2026-06-24): a location reminder takes precedence and clears the
        // time; otherwise the time "when" applies (when present).
        if let location = command.reminderLocation {
            d.locationReminder = location
            d.timeReminder = nil
        } else {
            d.locationReminder = nil
            if command.hasReminder {
                let when = command.reminderDate
                    ?? d.timeReminder?.scheduledDate
                    ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                d.timeReminder = TimeReminder(scheduledDate: when,
                                              notificationIdentifier: d.id.uuidString,
                                              alarmEnabled: command.reminderAlarm,
                                              isAllDay: command.reminderAllDay,
                                              recurrence: command.reminderRecurrence,
                                              weekdays: command.reminderRecurrence == .weekly ? command.reminderWeekdays : [])
            } else {
                d.timeReminder = nil
            }
        }

        // The fan's fourth Mark toggles Important now, not Obie (owner 2026-07-06). Apply
        // it straight to the draft — Important never conflicts (any number of Takes can be
        // Important), so there's no confirmation step. Obie is left untouched by the fan;
        // an Obie stays Important regardless, so OR it in.
        d.isImportant = command.isImportant || d.isObie

        d.normaliseActivityFloor()
        editDraft = d

        // Restore the editor keyboard after the ring (and its reminder picker) — the
        // ring-open path cleared focus, so re-assert it here. A freshly-added task
        // entry takes the caret; otherwise the first block does.
        let refocus = newTaskEntryID ?? d.blocks.first?.id
        editFocusedBlockID = nil
        if let refocus {
            DispatchQueue.main.async { editFocusedBlockID = refocus }
        }
    }

    /// "Make Obie" from the editing long-press menu (owner 2026-07-06 — replaced "Make
    /// Important" there; Important now lives on the Focus ring). Applies to the live draft
    /// so it rides the inline save. If another Obie already exists, warn first — exactly
    /// like the timeline long-press — leaving the flag off until confirmed.
    private func makeInlineObie() {
        guard app.ensureEntitled() else { return }
        guard var d = editDraft else { return }
        if !d.isObie, let other = vm.obie, other.id != d.id {
            pendingInlineObieConfirm = true
        } else {
            d.isObie = true
            d.normaliseActivityFloor()
            editDraft = d
            orientation.didDismissObieIntro()
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
                // Spotlight card only when this row ISN'T the one being edited — editing makes the
                // editor the context, and the spotlight's READ card over it reads as the Take
                // shrinking (owner 2026-07-16; the new timeline's editing card behaves the same).
                ui.openFocusRingFan(for: isEditingThis ? (editDraft ?? take) : take,
                                    origin: irisCentre, showsCard: !isEditingThis)
            },
            onLongPressCircle: {
                // Iris long-press is disabled during editing (discard moved to the
                // Take's long-press menu — owner 2026-06-17); a press on a masked row
                // just commits and exits.
                if editingActive { if !isEditingThis { saveInlineEdit() }; return }
                // Long-press now TOGGLES (owner 2026-07-04): a long-press on an Obie's
                // Iris turns it back into a standard Take. Demotion is NOT
                // entitlement-gated — removing a designation is always allowed, even on
                // a lapsed trial.
                if take.isObie { vm.demoteObie(take); return }
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
                // whole Take; a REPEATING reminder advances to its next occurrence instead
                // of pinning done (owner 2026-06-21), the same rule the at-rest path uses.
                // While editing, apply to the live draft so it rides the save; at rest,
                // toggle through the store.
                if isEditingThis {
                    guard var d = editDraft else { return }
                    d.toggleMarkedDoneAdvancingRecurring(now: Date())
                    editDraft = d
                    return
                }
                guard app.ensureEntitled() else { return }
                vm.toggleDone(take)
            },
            // Manual Important mark (owner 2026-06-19) — the RESTING timeline menu only.
            // While editing, this slot is given over to "Make Obie" instead (owner
            // 2026-07-06), so no onSetImportant is offered mid-edit.
            onSetImportant: isEditingThis ? nil : {
                guard app.ensureEntitled() else { return }
                var t = take
                t.isImportant.toggle()
                vm.save(t)
            },
            // Make Obie from the card long-press. On a RESTING row this is the
            // accessibility path (owner 2026-06-19), same designation as the Iris
            // long-press. WHILE EDITING it replaces "Make Important" in the menu (owner
            // 2026-07-06) and applies to the live draft via `makeInlineObie` — both warn
            // on conflict. Hidden only when the Take is already the Obie (menu gate).
            onMakeObie: isEditingThis
                ? { makeInlineObie() }
                : {
                    guard app.ensureEntitled() else { return }
                    vm.designateObie(take, replaceExisting: false)
                },
            onDelete: {
                guard app.ensureEntitled() else { return }
                deleteTake(take)
            },
            // Export this one Take (owner 2026-06-27). Exports what's on screen — the live
            // draft while editing, otherwise the stored Take — through the share sheet.
            // Subscription-independent, like the bulk export ("your data is yours, always").
            onExport: {
                ExportCoordinator.presentShareSheet(takes: [isEditingThis ? (editDraft ?? take) : take])
            },
            onDiscard: isEditingThis ? { discardInlineEdit() } : nil,
            // The editing row's Iris is the shape control (tap = Focus ring), so it
            // carries the retired editor's "editor-shape" id for tests + semantics.
            irisIdentifier: isEditingThis ? "editor-shape" : "take-iris",
            cardSwipeOffset: cardSwipeOffset,
            isSnoozed: vm.snoozedReminderIDs.contains(take.id),
            // Dimmed background rows during edit-in-place make their URLs inert, so a
            // save/discard tap can't open a link under the mask (owner 2026-06-27).
            linksInteractive: !(editingActive && !isEditingThis),
            // NO in-cell editor. Every edit rides the floating `TakeEditCard` (the M5a
            // consistency pass), and this row survives only to render the PINNED OBIE — building
            // an editor here gave two live editors on one draft: two Obies, and two UITextViews
            // fighting for first responder (device 2026-07-16). The seam stays on `TakeRowView`
            // for now; it is the last caller, so it can go with a `TakeRowView` trim.
            editingCard: nil
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

    /// The Takes the TIMELINE renders. The focused Take is edited IN PLACE in the
    /// timeline's own ScrollView (owner-agreed re-engineer 2026-06-19), which keeps
    /// native keyboard avoidance — so it stays in the list; `row(for:)` swaps in the
    /// inline editor for the row under focus. The other rows dim to 0.12 (see `row`).
    ///
    /// A NEW Take being created (not yet in `vm.takes`) is injected at the
    /// Order-appropriate end — bottom for Oldest-first, top for Newest-first — both at
    /// rest and while editing it.
    private var displayedTakes: [Take] {
        // The new Take is NO LONGER injected as a row (owner 2026-06-22) — it renders in the
        // keyboard-anchored `newTakeBlockCard`, which removes the fragile "scroll to an
        // off-screen far row" path entirely. It joins the timeline list only once saved.
        filteredTakes
    }

    // MARK: - Month grouping

    private struct MonthGroup { let key: String; let month: String; let takes: [Take] }

    /// Cached formatter — `DateFormatter` construction is expensive and this
    /// property is evaluated on every body pass.
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private var monthGroups: [MonthGroup] {
        // Key by the stable "yyyy-MM" bucket (the same key the month FILTER uses), in
        // first-seen order; the display string ("July 2026") is derived per group.
        var order: [String] = []
        var map: [String: [Take]] = [:]
        for take in displayedTakes {
            let key = SequenceFilter.monthKey(for: take.createdAt)
            if map[key] == nil { order.append(key); map[key] = [] }
            map[key]?.append(take)
        }
        return order.map { key in
            let display = Self.monthFormatter.string(from: (map[key]?.first?.createdAt) ?? Date())
            return MonthGroup(key: key, month: display, takes: map[key] ?? [])
        }
    }

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

/// Publishes the spine container's bottom edge (screen coords) for the search-terminus math.
private struct SpineContainerBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - UIScrollView capture (caret pin)

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
        // Three parallel tracks — centre + one either side (owner 2026-07-04). Every
        // spine element strokes this one shape, so the gutter and the through-Iris
        // wire stay one triple-tracked wire. Side lines fall outside the 2pt frame;
        // Shapes aren't clipped to their frame, so they render and the enclosing
        // `.offset` keeps all three centred on the spine.
        for dx in [-CatchlightLayout.spineTrackOffset, 0, CatchlightLayout.spineTrackOffset] {
            p.move(to: CGPoint(x: rect.midX + dx, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX + dx, y: rect.maxY))
        }
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
