//
//  BottomDockView.swift
//  Catchlight (iOS app target) — Phase 6 UI, one-surface dock redesign 2026-06-10
//
//  The persistent dock at the bottom of the ONE surface (the timeline). It morphs
//  between three states (UIState.DockMode), four slots left→right:
//
//    RESTING:   [+ Add Take][Dailies (active)][Sequence][Search]
//               Add creates a Take and opens the editor DIRECTLY (the old
//               two-option bloom is gone). Sequence → FILTERING;
//               Search → SEARCHING (via the merge-stretch morph below).
//    FILTERING: [+ Add Take][Notes][Tasks][Reminders]
//               Circular toggles, AND-composed live filters on the timeline.
//               Tap = off ↔ on; long-press Tasks/Reminders = on + modifier
//               ("Done" / "Expired") — the modifier shares the SAME Ember fill
//               as plain selected and is signalled by the swapped glyph alone
//               (owner rev 2026-06-11). Notes is mutually exclusive with the
//               other two. Exit = tapping empty timeline background (DailiesView).
//    SEARCHING: [× Cancel][— capsule text field spanning slots 2+3 —][Search]
//               × and Search sit EXACTLY on slot centres 1 & 4; the Take-white
//               capsule spans slots 2+3 (GeometryReader slot grid). No magnifier
//               in the field — just the Ember caret. Live per keystroke; slot-4
//               dismisses the keyboard; × morphs back to RESTING and clears.
//
//  Morph (cosmetic baseline 2026-06-11, HiFi v1.6 §9): entering search, the
//  Dailies and Sequence buttons glide toward the dock centre as their icons
//  dissolve, fuse, and the capsule stretches out of the fusion point with a
//  soft spring overshoot while + crossfades to ×. Exit mirrors it, quicker.
//  No rotation; everything stays inside the toolbar.
//
//  Settings access (owner redesign 2026-06-11): swipe UP anywhere on the dock
//  (drag beginning on the toolbar — deliberately NOT a screen-edge swipe, which
//  would fight the iOS home gesture). The old long-press on Dailies is retired;
//  VoiceOver keeps an explicit "Open Settings" action on the Dailies button.
//
//  One toolbar colour (owner): ALL icons Ember; state is carried by fill.
//  Dailies/Sequence use the custom spine glyphs (CatchlightGlyphs.swift).
//
//  The dock background is identical to the screen background (no elevation,
//  border, or separator). The Add button is the leftmost so the timeline spine
//  can terminate at its horizontal centre (RootView positions the spine to match
//  `addButtonCentreX`).
//
//  Long-press pattern: Button + .simultaneousGesture(LongPressGesture) — do NOT
//  switch to .onLongPressGesture; synthesized presses on the current simulator
//  runtime never reach it. Because the Button's tap action ALSO fires on
//  finger-up after a long press, each long-pressable toggle suppresses the
//  immediately following tap via a one-shot flag.
//

import SwiftUI
import CatchlightCore

struct BottomDockView: View {
    @Environment(UIState.self) private var ui
    @Environment(FirstRunOrientationState.self) private var orientation
    @Environment(\.dynamicTypeSize) private var dynamicSize
    /// For the per-type filter-toggle fills (owner 2026-06-18): each filter's ON fill
    /// uses its Iris quadrant colour, which is scheme-dependent.
    @Environment(\.colorScheme) private var scheme
    /// Bottom safe-area inset (home-indicator zone), captured at the window root.
    /// Section 4 / D-041 — the full-bleed dock never re-added the bottom inset,
    /// so on a device with a home indicator it sat ~8pt off the physical edge,
    /// inside the indicator zone. Padding by `deviceBottomInset + 8` rests it
    /// above the indicator.
    @Environment(\.deviceBottomInset) private var deviceBottomInset
    // Live-updating, unlike reading `UIAccessibility.isReduceMotionEnabled`
    // directly (which only reflects the setting at call time).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Create a Take and open the editor (gated by the paywall in RootView).
    /// Available in RESTING and FILTERING.
    var onNewTake: () -> Void

    private let buttonSize: CGFloat = CatchlightLayout.minTouchTarget
    /// Visible dock-circle diameter. Owner 2026-06-15: enlarged 36 → 44 so the
    /// circle FILLS its 44pt touch frame (= `minTouchTarget`) — the buttons read
    /// larger and now match the onboarding/paywall pill, which already sizes to the
    /// 44pt grid (DockPillRow). Slot centres are unchanged, so the buttons keep
    /// their distance from the screen edges and only sit visually closer together.
    /// Glyphs were scaled in step (×44/36) to preserve the HiFi glyph-to-circle
    /// ratio. All resting dock buttons draw this circle — a 1.5pt Ember-tinted
    /// border around the icon (.db) — so they read as circles rather than bare
    /// icons (section 6). Filled buttons (+, on-toggles, the × cancel) use the same
    /// diameter so the dock stays visually uniform and the off→on toggle doesn't
    /// jump size.
    private let dockCircle: CGFloat = 44

    /// The resting border ring shared by every dock button (HiFi v1.7 .db).
    /// Uniform Ember @ 0.55, 1.5pt across ALL dock buttons (owner 2026-06-19).
    /// The old two-tier split (0.55 for Add + active Dailies, 0.35 for
    /// Sequence/Search and the filter/cancel rings) read as a colour mismatch
    /// between the slot pairs, so it's retired in favour of one weight.
    private func dockRing() -> some View {
        Circle()
            .strokeBorder(Color.ckAccent.opacity(0.55), lineWidth: 1.5)
            .frame(width: dockCircle, height: dockCircle)
            .allowsHitTesting(false)
    }

    /// Number of completed pulses for the first-run Add hint. We pulse exactly twice
    /// then stop — never loop. Re-set to 0 if the hint is dismissed and re-armed.
    @State private var addPulseScale: CGFloat = 1.0
    @State private var addPulsesDone = 0

    /// One-shot guards: a long-press on a toggle also delivers the Button tap
    /// on finger-up; these swallow that single trailing tap.
    @State private var suppressTasksTap = false
    @State private var suppressRemindersTap = false

    /// Autofocus for the SEARCHING-state capsule field.
    @FocusState private var searchFocused: Bool

    // ── Morph state (resting ⇄ searching) ──
    /// 0→1 while Dailies/Sequence glide toward the dock centre (icons dissolve).
    @State private var mergeProgress: CGFloat = 0
    /// Capsule width: false = the fused 44pt droplet, true = full slots 2+3.
    @State private var capsuleExpanded = true
    /// Re-entrancy guard while a morph sequence is running.
    @State private var morphing = false

    var body: some View {
        @Bindable var ui = ui
        GeometryReader { geo in
            // Four equal slots inside the horizontal padding — the same grid
            // CatchlightLayout.spineX derives from, so × (searching) lands on
            // the + slot centre and Search stays put.
            let slotW = geo.size.width / 4
            HStack(spacing: 0) {
                switch ui.dockMode {
                case .resting:
                    addButton.frame(width: slotW)
                    dailiesNavButton
                        .frame(width: slotW)
                        .offset(x: mergeProgress * slotW * 0.5)
                        .opacity(1 - Double(mergeProgress))
                    sequenceNavButton
                        .frame(width: slotW)
                        .offset(x: -mergeProgress * slotW * 0.5)
                        .opacity(1 - Double(mergeProgress))
                    searchNavButton.frame(width: slotW)
                case .filtering:
                    addButton.frame(width: slotW)
                    notesToggle.frame(width: slotW)
                    tasksToggle.frame(width: slotW)
                    remindersToggle.frame(width: slotW)
                case .searching:
                    searchCancelButton.frame(width: slotW)
                    searchField
                        .frame(width: capsuleExpanded ? slotW * 2 : buttonSize)
                        .frame(width: slotW * 2)   // reserve slots 2+3; droplet centres in them
                    searchDismissButton.frame(width: slotW)
                }
            }
        }
        // First-run Hint 3 — centred on the dock's x-axis (= screen centre),
        // not the off-centre Dailies slot it used to hang over (owner 2026-06-16).
        // The GeometryReader spans the full padded dock width, so `.top`-centre
        // alignment lands the bubble dead-centre; the same vertical offset as
        // before keeps it floating just above the toolbar.
        .overlay(alignment: .top) {
            if orientation.showSettingsHint {
                OrientationTooltip(text: "Swipe up here for settings.", arrowEdge: .bottom)
                    .fixedSize()
                    .offset(y: -(buttonSize / 2 + 32))
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                    .allowsHitTesting(false)
            }
        }
        .frame(height: buttonSize)
        .animation(.easeInOut(duration: 0.2), value: ui.dockMode)
        .padding(.horizontal, CatchlightLayout.dockHorizontalPadding)
        .padding(.top, 10)
        // Section 4 / D-041 — rest above the home indicator (was a bare 8).
        .padding(.bottom, deviceBottomInset + CatchlightLayout.dockBottomPadding)
        // Soft bottom edge (HiFi §1 / v1.6 owner directive: "the toolbar has no
        // hard edge that the Takes disappear behind" — they fade beneath it).
        // D-042; was a solid Color.ckBackground fill.
        .dockFadeBackground()
        // Settings: swipe up anywhere on the dock (owner redesign 2026-06-11 —
        // replaces the long-press on Dailies; not a screen-edge gesture, so it
        // never fights the system home swipe).
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard value.translation.height < -30,
                          abs(value.translation.width) < 60 else { return }
                    if orientation.showSettingsHint {
                        // Hint 3 still up — dismiss the hint without opening
                        // (spec: visual only during the hint).
                        orientation.didDismissSettingsHint()
                    } else {
                        ui.isSettingsPresented = true
                    }
                }
        )
        .onChange(of: ui.dockMode) { _, mode in
            // Announce the morph so VoiceOver users know the dock changed
            // underneath them (the four buttons are replaced wholesale).
            let announcement: String
            switch mode {
            case .resting: announcement = "Dock returned to navigation."
            case .filtering: announcement = "Dock showing timeline filters."
            case .searching: announcement = "Dock showing search."
            }
            UIAccessibility.post(notification: .layoutChanged, argument: announcement)
        }
    }

    // MARK: - Add button (RESTING + FILTERING)

    private var addButton: some View {
        Button {
            // Tapping Add dismisses Hint 1 (state machine ignores if not active).
            orientation.didTapAdd()
            // Redesign 2026-06-10: no bloom — Add creates the Take and opens
            // the editor directly (capture is two taps incl. the typing commit).
            onNewTake()
        } label: {
            ZStack {
                // HiFi `.db.add` is an OUTLINE button — a stronger Ember border,
                // NOT a fill (D-042 follow-up, owner 2026-06-14). The only filled
                // dock state is a SELECTED FILTER TOGGLE (see toggleLabel .on/.mod);
                // Add and active-Dailies are distinguished by the 0.55 border, not
                // a fill. Was a filled ckAdd droplet with an Ink "+".
                dockRing()   // .db.add — Ember border @55%
                Image(systemName: "plus")
                    // .regular (was .medium): the + read slightly heavier than the
                    // .light sibling glyphs; nudged down one step (owner 2026-06-16).
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Color.ckAccent)   // #856539 glyph (Option A), like the siblings
            }
            .frame(width: buttonSize, height: buttonSize)
            .scaleEffect(addPulseScale)
            // Add is the LEFTMOST dock slot (≈58pt from the screen edge), so a
            // centred bubble clipped off-screen left. Anchor the arrow at the
            // bubble's bottom-LEADING (over the +) and let the bubble extend RIGHT
            // (owner 2026-06-15): .topLeading lines the bubble's leading up with the
            // button's, the arrow sits 22pt in (the + centre), text spills right.
            .overlay(alignment: .topLeading) {
                if orientation.showAddPulse {
                    OrientationTooltip(text: "What's your first Take?", arrowEdge: .bottom, arrowAlignment: .leading)
                        .fixedSize()
                        .offset(y: -(buttonSize / 2 + 32))
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottomLeading)))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("add-button")
        .accessibilityLabel("Add Take")
        .accessibilityHint("Double-tap to capture a new Take.")
        .accessibilityAddTraits(.isButton)
        .onChange(of: orientation.showAddPulse, initial: true) { _, showing in
            if showing { startAddPulseIfAllowed() } else { addPulsesDone = 2; addPulseScale = 1.0 }
        }
    }

    /// Two-cycle pulse on the Add button for first-run Hint 1. Respects Reduce Motion
    /// (skips the animation but leaves the tooltip visible).
    private func startAddPulseIfAllowed() {
        addPulsesDone = 0
        addPulseScale = 1.0
        if reduceMotion { return }
        runPulseCycle()
    }

    private func runPulseCycle() {
        guard orientation.showAddPulse, addPulsesDone < 2 else { return }
        withAnimation(.easeInOut(duration: 0.45)) { addPulseScale = 1.18 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeInOut(duration: 0.45)) { addPulseScale = 1.0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                addPulsesDone += 1
                runPulseCycle()
            }
        }
    }

    // MARK: - RESTING nav buttons

    /// The Dailies nav button — always the active surface (there is only one).
    /// Settings moved to the dock swipe-up (owner redesign 2026-06-11); while
    /// first-run Hint 3 is visible a tap dismisses the hint, shown with a
    /// dashed ring + tooltip. The custom spine glyph IS the Dailies icon.
    private var dailiesNavButton: some View {
        Button {
            if orientation.showSettingsHint { orientation.didDismissSettingsHint() }
        } label: {
            ZStack {
                if orientation.showSettingsHint {
                    Circle()
                        .strokeBorder(
                            Color.ckAdd.opacity(0.6),
                            style: StrokeStyle(lineWidth: 2, dash: [5, 4])
                        )
                        .frame(width: buttonSize, height: buttonSize)
                        .transition(.opacity)
                }
                dockRing()   // .db.active — Ember border @55%
                DailiesGlyph(size: 24)   // scaled with the 36→44 circle
                    .foregroundStyle(Color.ckAccent)
                    .frame(width: buttonSize, height: buttonSize)
                    .contentShape(Rectangle())
            }
            // The "Swipe up here for settings." tooltip is NOT hosted here any
            // more — the swipe gesture lives on the whole dock, not this button,
            // so a bubble centred on the off-centre Dailies slot read as lopsided.
            // It now sits centred on the dock's x-axis (see `settingsHint` on the
            // dock body, owner 2026-06-16). The dashed ring stays on this button
            // as the visual "tap to dismiss" target.
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dailies-tab")
        .accessibilityLabel("Dailies")
        .accessibilityValue("selected")
        .accessibilityHint("Your timeline. Swipe up on the toolbar to open Settings.")
        // The swipe is a VoiceOver-incompatible gesture, so expose Settings as
        // an explicit named action too.
        .accessibilityAction(named: "Open Settings") { ui.isSettingsPresented = true }
        .accessibilityAddTraits([.isSelected, .isButton])
    }

    /// Sequence (slot 3, RESTING) — morphs the dock to the FILTERING state.
    /// Three beads on the spine: a sequence of Takes (sibling of the Dailies glyph).
    private var sequenceNavButton: some View {
        Button {
            ui.enterFiltering()
        } label: {
            ZStack {
                dockRing()   // .db — Ember border @35%
                SequenceGlyph(size: 24)   // scaled with the 36→44 circle
                    // Owner 2026-06-16: lay the three beads HORIZONTALLY (a left→
                    // right sequence) while Dailies stays vertical. Rotating the
                    // glyph view keeps the shape's bead/link geometry intact.
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(Color.ckAccent)
                    .frame(width: buttonSize, height: buttonSize)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sequence-tab")
        .accessibilityLabel("Sequence")
        .accessibilityHint("Double-tap to filter the timeline by notes, tasks, or reminders.")
        .accessibilityAddTraits(.isButton)
    }

    /// Search (slot 4, RESTING) — runs the merge-stretch morph into SEARCHING.
    private var searchNavButton: some View {
        Button {
            morphToSearch()
        } label: {
            navIcon("magnifyingglass")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search-tab")
        .accessibilityLabel("Search")
        .accessibilityHint("Double-tap to search your Takes.")
        .accessibilityAddTraits(.isButton)
    }

    /// One toolbar colour (owner, cosmetic baseline): every dock icon is Ember,
    /// at the light weight from the refined icon set. (Daylight resolves Ember
    /// to the accessible #856539 via `ckAccent` — D-028.)
    private func navIcon(_ system: String) -> some View {
        ZStack {
            dockRing()   // .db — Ember border @35% (Sequence / Search resting)
            Image(systemName: system)
                .font(.system(size: 24, weight: .light))   // scaled with the 36→44 circle
                .foregroundStyle(Color.ckAccent)
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
        }
    }

    // MARK: - Resting ⇄ searching morph

    /// Dailies + Sequence glide together (icons dissolving), fuse, and the
    /// capsule stretches out of the fusion point; + crossfades to ×. The whole
    /// gesture lives inside the toolbar — no rotation. Reduce Motion gets the
    /// plain crossfade the dock already does on mode changes.
    private func morphToSearch() {
        guard !morphing else { return }
        guard !reduceMotion else { ui.enterSearching(); searchFocused = true; return }
        morphing = true
        withAnimation(.easeInOut(duration: 0.28)) { mergeProgress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.29) {
            capsuleExpanded = false
            ui.enterSearching()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                capsuleExpanded = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                searchFocused = true
                mergeProgress = 0
                morphing = false
            }
        }
    }

    /// Exit mirror, quicker: capsule contracts to the droplet, which splits
    /// back into Dailies + Sequence as their icons breathe back in.
    private func morphFromSearch() {
        guard !morphing else { return }
        guard !reduceMotion else { ui.exitToResting(); return }
        morphing = true
        searchFocused = false
        withAnimation(.easeIn(duration: 0.22)) { capsuleExpanded = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
            mergeProgress = 1
            ui.exitToResting()
            withAnimation(.easeOut(duration: 0.26)) { mergeProgress = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) {
                capsuleExpanded = true
                morphing = false
            }
        }
    }

    // MARK: - FILTERING toggles

    /// Visual vocabulary for the three filter-toggle states (owner rev 2026-06-11):
    ///   off      — bare Ember glyph (one toolbar colour; state = fill, not hue)
    ///   on       — circle filled with Ember + background-colour glyph (reversed)
    ///   modified — the SAME Ember fill as `on`; the swapped glyph ALONE signals
    ///              the modifier (checkmark.circle = Done, clock.badge.exclamationmark = Expired)
    private enum ToggleVisual { case off, on, modified }

    /// `onFill` is the toggle's ON/modified fill — each filter passes its Iris quadrant
    /// colour so the dock toggle matches the Iris that type lights up (owner 2026-06-18).
    /// The ON icon is `ckBackground` (the page colour) so it contrasts against ANY fill
    /// in BOTH modes — the same "aperture" read as the Iris's hollow centre (the old
    /// `ckOnAccent`/Ink icon went dark-on-dark over the new mid-tone Daylight fills).
    private func toggleLabel(system: String, visual: ToggleVisual, onFill: Color = .ckEmber) -> some View {
        ZStack {
            switch visual {
            case .off:
                // .db.toggle off = bare Ember icon inside the resting .db ring.
                dockRing()
            case .on, .modified:
                // Fill the toggle with its type colour (the fill edge IS the border).
                Circle().fill(onFill)
                    .frame(width: dockCircle, height: dockCircle)
            }
            Image(systemName: system)
                .font(.system(size: 22, weight: .light))   // scaled with the 36→44 circle
                .foregroundStyle(visual == .off ? Color.ckAccent : Color.ckBackground)
        }
        .frame(width: buttonSize, height: buttonSize)
        .contentShape(Circle())
    }

    /// Notes — plain on/off toggle, mutually exclusive with Tasks/Reminders.
    private var notesToggle: some View {
        Button {
            ui.tapNotesFilter()
        } label: {
            toggleLabel(system: "note.text", visual: ui.filterNotes ? .on : .off,
                        onFill: Quadrant.note(scheme))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filter-notes")
        .accessibilityLabel("Notes filter")
        .accessibilityValue(ui.filterNotes ? "on" : "off")
        .accessibilityHint("Double-tap to show only pure notes. Turning notes on clears the tasks and reminders filters.")
        .accessibilityAddTraits(ui.filterNotes ? [.isSelected, .isButton] : [.isButton])
    }

    /// Tasks — tap toggles; long-press sets the "Done" (completed only) modifier.
    private var tasksToggle: some View {
        let visual: ToggleVisual = ui.filterTasksDone ? .modified : (ui.filterTasks ? .on : .off)
        return Button {
            if suppressTasksTap { suppressTasksTap = false; return }
            ui.tapTasksFilter()
        } label: {
            toggleLabel(system: ui.filterTasksDone ? "checkmark.circle" : "checkmark.square",
                        visual: visual, onFill: Quadrant.task(scheme))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                suppressTasksTap = true   // swallow the trailing Button tap
                ui.longPressTasksFilter()
            }
        )
        .accessibilityIdentifier("filter-tasks")
        .accessibilityLabel("Tasks filter")
        .accessibilityValue(ui.filterTasksDone ? "done only" : (ui.filterTasks ? "on" : "off"))
        .accessibilityHint("Double-tap to toggle. Long press for completed tasks only.")
        // Long-press is VoiceOver-incompatible — expose the modifier as a named action.
        .accessibilityAction(named: "Completed tasks only") { ui.longPressTasksFilter() }
        .accessibilityAddTraits(ui.filterTasks ? [.isSelected, .isButton] : [.isButton])
    }

    /// Reminders — tap toggles; long-press sets the "Expired" (date passed) modifier.
    private var remindersToggle: some View {
        let visual: ToggleVisual = ui.filterRemindersExpired ? .modified : (ui.filterReminders ? .on : .off)
        return Button {
            if suppressRemindersTap { suppressRemindersTap = false; return }
            ui.tapRemindersFilter()
        } label: {
            toggleLabel(system: ui.filterRemindersExpired ? "clock.badge.exclamationmark" : "bell",
                        visual: visual, onFill: Quadrant.reminder(scheme))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                suppressRemindersTap = true   // swallow the trailing Button tap
                ui.longPressRemindersFilter()
            }
        )
        .accessibilityIdentifier("filter-reminders")
        .accessibilityLabel("Reminders filter")
        .accessibilityValue(ui.filterRemindersExpired ? "expired only" : (ui.filterReminders ? "on" : "off"))
        .accessibilityHint("Double-tap to toggle. Long press for expired reminders only.")
        .accessibilityAction(named: "Expired reminders only") { ui.longPressRemindersFilter() }
        .accessibilityAddTraits(ui.filterReminders ? [.isSelected, .isButton] : [.isButton])
    }

    // MARK: - SEARCHING state

    /// × (slot 1 — exactly where + sits at rest) — morphs back to RESTING and
    /// clears the query.
    private var searchCancelButton: some View {
        Button {
            morphFromSearch()
        } label: {
            ZStack {
                Circle().fill(Color.ckSurface)
                    .frame(width: dockCircle, height: dockCircle)
                dockRing()   // .db — Ember border @35%
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .light))   // scaled with the 36→44 circle
                    .foregroundStyle(Color.ckAccent)
            }
            .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search-cancel")
        .accessibilityLabel("Cancel search")
        .accessibilityHint("Double-tap to clear the search and return to the dock.")
        .accessibilityAddTraits(.isButton)
    }

    /// The merged capsule field spanning slots 2+3 — the two circles fused.
    /// Take-card surface, Take-row type, NO magnifier — just the Ember caret
    /// (owner: the field on first view is the blinking cursor alone). Focus is
    /// driven by the morph (or onAppear as a fallback for direct entry).
    private var searchField: some View {
        @Bindable var ui = ui
        return TextField("Search your Takes", text: $ui.searchQuery)
            .focused($searchFocused)
            // §5: the search field is Take-row type — DM Sans 14, not the
            // display face (D-042; was Cormorant display 20).
            .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .body))
            .foregroundStyle(Color.ckTextPrimary)
            .tint(Color.ckEmber)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit { searchFocused = false }
            .accessibilityIdentifier("search-field")
            .accessibilityLabel("Search Takes")
            .accessibilityHint("Type to filter the timeline by text.")
            .padding(.horizontal, 16)
            .frame(height: buttonSize)
            .background(Capsule().fill(Color.ckSurface))
    }

    /// Search (slot 4, SEARCHING) — dismisses the keyboard; the Return-key
    /// equivalent. The query (and live filtering) stays.
    private var searchDismissButton: some View {
        Button {
            searchFocused = false
        } label: {
            navIcon("magnifyingglass")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search-tab")
        .accessibilityLabel("Search")
        .accessibilityHint("Double-tap to dismiss the keyboard and review results.")
        .accessibilityAddTraits(.isButton)
    }

    /// The x of the Add button's centre within the dock's coordinate space, so the
    /// caller can terminate the spine there. Delegates to the single source of
    /// truth in CatchlightLayout — DailiesView derives its spine x from the same
    /// formula, which is what keeps the spine on the + vertical (2026-06-10 fix).
    static func addButtonCentreX(dockWidth: CGFloat) -> CGFloat {
        CatchlightLayout.spineX(containerWidth: dockWidth)
    }
}

#Preview("Dock — resting (Night)") {
    VStack {
        Spacer()
        BottomDockView(onNewTake: {})
            .environment(UIState())
            .environment(FirstRunOrientationState())
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}

#Preview("Dock — filtering") {
    let ui = UIState()
    ui.enterFiltering()
    ui.filterTasks = true
    ui.filterRemindersExpired = true
    ui.filterReminders = true
    return VStack {
        Spacer()
        BottomDockView(onNewTake: {})
            .environment(ui)
            .environment(FirstRunOrientationState())
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}

#Preview("Dock — searching") {
    let ui = UIState()
    ui.enterSearching()
    return VStack {
        Spacer()
        BottomDockView(onNewTake: {})
            .environment(ui)
            .environment(FirstRunOrientationState())
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.light)
}
