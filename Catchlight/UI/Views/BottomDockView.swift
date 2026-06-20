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

    /// Retained for the resting-dock layout (Dailies/Sequence offset/opacity read it);
    /// stays 0 now that search no longer morphs the dock (the field rides the keyboard,
    /// 2026-06-20), so those buttons simply sit still.
    @State private var mergeProgress: CGFloat = 0

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
                    angleNavButton
                        .frame(width: slotW)
                        .offset(x: mergeProgress * slotW * 0.5)
                        .opacity(1 - Double(mergeProgress))
                    sequenceNavButton
                        .frame(width: slotW)
                        .offset(x: -mergeProgress * slotW * 0.5)
                        .opacity(1 - Double(mergeProgress))
                    searchNavButton.frame(width: slotW)
                case .filtering:
                    importantToggle.frame(width: slotW)
                    notesToggle.frame(width: slotW)
                    tasksToggle.frame(width: slotW)
                    remindersToggle.frame(width: slotW)
                case .searching:
                    if ui.searchKeyboardUp {
                        // Keyboard + the docked search bar are up; the bottom dock sits
                        // BEHIND the keyboard, so render nothing here — and crucially
                        // avoid a second `search-field`/`search-cancel` in the tree.
                        Color.clear.frame(maxWidth: .infinity)
                    } else {
                        // Keyboard lowered but still searching: a tap-to-resume bar so
                        // results stay browsable and the keyboard can come back.
                        searchCancelButton.frame(width: slotW)
                        searchResumeField.frame(width: slotW * 2)
                        searchDismissButton.frame(width: slotW)
                    }
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

    /// The Angle nav button (slot 2, RESTING) — opens the STORYBOARD ANGLE, the
    /// full-screen list of every task-bearing Take (owner 2026-06-19). Replaces the
    /// old Dailies button, which was inert now there is one surface: its tap only
    /// ever dismissed the settings hint. The settings swipe-up still lives on the
    /// WHOLE dock; while the first-run settings hint is up a tap dismisses it (the
    /// dashed ring is the "tap to dismiss" target), and the explicit "Open Settings"
    /// VoiceOver action moves here. The glyph is the literal angle (∠) — distinct
    /// from the keyboard Angle's checklist glyph, so each icon hints what it opens
    /// (the Storyboard vs a single Take's list).
    private var angleNavButton: some View {
        Button {
            if orientation.showSettingsHint {
                orientation.didDismissSettingsHint()
            } else {
                ui.isStoryboardPresented = true
            }
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
                dockRing()
                Image(systemName: "angle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color.ckAccent)
                    // The ∠ symbol's mass sits low-left, so centred in the ring it
                    // reads as sitting low — nudge it up ~2pt to optically centre
                    // (owner 2026-06-19). Tunable.
                    .offset(y: -2)
                    .frame(width: buttonSize, height: buttonSize)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("angle-tab")
        .accessibilityLabel("Storyboard")
        .accessibilityHint("Opens the Storyboard — every Take with a task. Swipe up on the toolbar to open Settings.")
        // The swipe is a VoiceOver-incompatible gesture, so expose Settings as
        // an explicit named action too.
        .accessibilityAction(named: "Open Settings") { ui.isSettingsPresented = true }
        .accessibilityAddTraits(.isButton)
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
            // Enter search — the keyboard + the docked search bar (KeyboardSearchBar,
            // a UIKit inputAccessoryView in RootView) come up. No in-dock morph: the
            // search field now rides the keyboard, not the bottom dock (owner 2026-06-20).
            ui.enterSearching()
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

    /// Important (slot 1, FILTERING) — replaces the Add button while filtering
    /// (owner 2026-06-19: all filters now live under Sequence). Off ↔ on; orthogonal
    /// to the type toggles, so it neither clears them nor is cleared. Uses the
    /// Dailies glyph — the app's Important glyph — and the shared Ember ON fill.
    private var importantToggle: some View {
        Button {
            ui.tapImportantFilter()
        } label: {
            ZStack {
                if ui.filterImportant {
                    Circle().fill(Color.ckEmber)
                        .frame(width: dockCircle, height: dockCircle)
                } else {
                    dockRing()
                }
                DailiesGlyph(size: 22)
                    .foregroundStyle(ui.filterImportant ? Color.ckBackground : Color.ckAccent)
            }
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filter-important")
        .accessibilityLabel("Important filter")
        .accessibilityValue(ui.filterImportant ? "on" : "off")
        .accessibilityHint("Double-tap to show only Important Takes.")
        .accessibilityAddTraits(ui.filterImportant ? [.isSelected, .isButton] : [.isButton])
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

    // MARK: - SEARCHING state (keyboard-lowered "resume" bar)
    //
    // The editable search field rides the keyboard as a UIKit inputAccessoryView
    // (`KeyboardSearchBar`, presented in RootView) — the device-reliable mechanism,
    // 2026-06-20. These dock controls appear ONLY when the keyboard has been lowered
    // (`!ui.searchKeyboardUp`) but search is still active: a tap-to-resume bar so the
    // results stay browsable and the keyboard can be brought back.

    /// × (slot 1 — exactly where + sits at rest) — leaves search and clears the query.
    private var searchCancelButton: some View {
        Button {
            ui.exitToResting()
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

    /// The capsule spanning slots 2+3 — a non-editable display of the current query
    /// (or the placeholder). Tapping it brings the keyboard + the docked search bar
    /// back up to keep typing.
    private var searchResumeField: some View {
        Button {
            ui.raiseSearchKeyboard()
        } label: {
            HStack {
                Text(ui.searchQuery.isEmpty ? "Search your Takes" : ui.searchQuery)
                    .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .body))
                    .foregroundStyle(ui.searchQuery.isEmpty ? Color.ckTextSecondary : Color.ckTextPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: buttonSize)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.ckSurface))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search-resume")
        .accessibilityLabel("Search Takes")
        .accessibilityValue(ui.searchQuery)
        .accessibilityHint("Double-tap to resume typing your search.")
    }

    /// Magnifier (slot 4) — while the keyboard is lowered, brings it back up to type.
    private var searchDismissButton: some View {
        Button {
            ui.raiseSearchKeyboard()
        } label: {
            navIcon("magnifyingglass")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search-tab")
        .accessibilityLabel("Search")
        .accessibilityHint("Double-tap to bring the keyboard back and keep typing.")
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
