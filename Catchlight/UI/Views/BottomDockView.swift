//
//  BottomDockView.swift
//  Catchlight (iOS app target) — Phase 6 UI, one-surface dock redesign 2026-06-10
//
//  The persistent dock at the bottom of the ONE surface (the timeline). It morphs
//  between three states (UIState.DockMode), four slots left→right:
//
//    RESTING:   [+ Add Take][Dailies (active)][Sequence][Search]
//               Add creates a Take and opens the editor DIRECTLY (the old
//               two-option bloom is gone). Long-press Dailies → Settings.
//               Sequence → FILTERING; Search → SEARCHING.
//    FILTERING: [+ Add Take][Notes][Tasks][Reminders]
//               Circular toggles, AND-composed live filters on the timeline.
//               Tap = off ↔ on; long-press Tasks/Reminders = on + modifier
//               ("Done" / "Expired"); Notes is mutually exclusive with the
//               other two. Exit = tapping empty timeline background (DailiesView).
//    SEARCHING: [× Cancel][— capsule text field spanning slots 2+3 —][Search]
//               The field autofocuses; filtering is live per keystroke. The
//               slot-4 Search button just dismisses the keyboard (Return-key
//               equivalent); × exits to RESTING and clears the query.
//
//  The dock background is identical to the screen background (no elevation,
//  border, or separator). The Add button is the leftmost so the timeline spine
//  can terminate at its horizontal centre (RootView positions the spine to match
//  `addButtonCentreX`).
//
//  Long-press pattern: Button + .simultaneousGesture(LongPressGesture) — the
//  same pattern as the Dailies/Settings press. Do NOT switch to
//  .onLongPressGesture; synthesized presses on the current simulator runtime
//  never reach it. Because the Button's tap action ALSO fires on finger-up
//  after a long press, each long-pressable toggle suppresses the immediately
//  following tap via a one-shot flag.
//

import SwiftUI
import CatchlightCore

struct BottomDockView: View {
    @Environment(UIState.self) private var ui
    @Environment(FirstRunOrientationState.self) private var orientation
    @Environment(\.dynamicTypeSize) private var dynamicSize
    // Live-updating, unlike reading `UIAccessibility.isReduceMotionEnabled`
    // directly (which only reflects the setting at call time).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Create a Take and open the editor (gated by the paywall in RootView).
    /// Available in RESTING and FILTERING.
    var onNewTake: () -> Void

    private let buttonSize: CGFloat = CatchlightLayout.minTouchTarget

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

    var body: some View {
        @Bindable var ui = ui
        HStack(spacing: 0) {
            switch ui.dockMode {
            case .resting:
                addButton.frame(maxWidth: .infinity)
                dailiesNavButton.frame(maxWidth: .infinity)
                sequenceNavButton.frame(maxWidth: .infinity)
                searchNavButton.frame(maxWidth: .infinity)
            case .filtering:
                addButton.frame(maxWidth: .infinity)
                notesToggle.frame(maxWidth: .infinity)
                tasksToggle.frame(maxWidth: .infinity)
                remindersToggle.frame(maxWidth: .infinity)
            case .searching:
                searchCancelButton.frame(maxWidth: .infinity)
                searchField.frame(maxWidth: .infinity)   // spans slots 2+3
                searchDismissButton.frame(maxWidth: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: ui.dockMode)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.ckBackground)   // identical to screen — no elevation
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
                Circle().fill(Color.ckAdd)
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.ckBackground)
            }
            .frame(width: buttonSize, height: buttonSize)
            .scaleEffect(addPulseScale)
            .overlay(alignment: .top) {
                if orientation.showAddPulse {
                    OrientationTooltip(text: "What's your first Take?", arrowEdge: .bottom)
                        .fixedSize()
                        .offset(y: -(buttonSize / 2 + 32))
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
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
    /// Long-press opens Settings; while first-run Hint 3 is visible the press
    /// dismisses the hint without activating Settings ("visual only" rule),
    /// shown with a dashed ring + tooltip.
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
                Image(systemName: "list.bullet")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.ckNavActive)
                    .frame(width: buttonSize, height: buttonSize)
                    .contentShape(Rectangle())
            }
            .overlay(alignment: .top) {
                if orientation.showSettingsHint {
                    OrientationTooltip(text: "Long press here for settings.", arrowEdge: .bottom)
                        .fixedSize()
                        .offset(y: -(buttonSize / 2 + 32))
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                }
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                if orientation.showSettingsHint {
                    // Hint 3 still up — dismiss the hint visually without opening
                    // Settings (spec: "Long-press gesture is DISABLED during this
                    // hint — visual only, cannot activate settings").
                    orientation.didDismissSettingsHint()
                } else {
                    // Orientation complete: long-press opens the Settings sheet (6.14).
                    ui.isSettingsPresented = true
                }
            }
        )
        .accessibilityIdentifier("dailies-tab")
        .accessibilityLabel("Dailies")
        .accessibilityValue("selected")
        .accessibilityHint("Your timeline. Long press to open Settings.")
        // Long-press → Settings is a VoiceOver-incompatible gesture (VO intercepts
        // long press), so expose Settings as an explicit named action too.
        .accessibilityAction(named: "Open Settings") { ui.isSettingsPresented = true }
        .accessibilityAddTraits([.isSelected, .isButton])
    }

    /// Sequence (slot 3, RESTING) — morphs the dock to the FILTERING state.
    private var sequenceNavButton: some View {
        Button {
            ui.enterFiltering()
        } label: {
            navIcon("square.stack.3d.up", active: false)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sequence-tab")
        .accessibilityLabel("Sequence")
        .accessibilityHint("Double-tap to filter the timeline by Notes, Tasks, or Reminders.")
        .accessibilityAddTraits(.isButton)
    }

    /// Search (slot 4, RESTING) — morphs the dock to the SEARCHING state.
    private var searchNavButton: some View {
        Button {
            ui.enterSearching()
        } label: {
            navIcon("magnifyingglass", active: false)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search-tab")
        .accessibilityLabel("Search")
        .accessibilityHint("Double-tap to search your Takes.")
        .accessibilityAddTraits(.isButton)
    }

    private func navIcon(_ system: String, active: Bool) -> some View {
        Image(systemName: system)
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(active ? Color.ckNavActive : Color.ckNavInactive)
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(Rectangle())
    }

    // MARK: - FILTERING toggles

    /// Visual vocabulary for the three filter-toggle states:
    ///   off      — like an inactive nav circle (bare icon, ckNavInactive)
    ///   on       — circle filled with ckAdd (the old selected-pill colour)
    ///   modified — circle filled with ckEmber + a distinct SF symbol
    ///              (checkmark.circle = Done, clock.badge.exclamationmark = Expired)
    private enum ToggleVisual { case off, on, modified }

    private func toggleLabel(system: String, visual: ToggleVisual) -> some View {
        ZStack {
            switch visual {
            case .off:
                Circle().fill(Color.clear)
            case .on:
                Circle().fill(Color.ckAdd)
            case .modified:
                Circle().fill(Color.ckEmber)
            }
            Image(systemName: system)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(visual == .off ? Color.ckNavInactive : Color.ckBackground)
        }
        .frame(width: buttonSize, height: buttonSize)
        .contentShape(Circle())
    }

    /// Notes — plain on/off toggle, mutually exclusive with Tasks/Reminders.
    private var notesToggle: some View {
        Button {
            ui.tapNotesFilter()
        } label: {
            toggleLabel(system: "note.text", visual: ui.filterNotes ? .on : .off)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filter-notes")
        .accessibilityLabel("Notes filter")
        .accessibilityValue(ui.filterNotes ? "on" : "off")
        .accessibilityHint("Double-tap to show only pure notes. Turning Notes on clears the Tasks and Reminders filters.")
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
                        visual: visual)
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
                        visual: visual)
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

    /// × (slot 1) — exits to RESTING and clears the query.
    private var searchCancelButton: some View {
        Button {
            searchFocused = false
            ui.exitToResting()
        } label: {
            ZStack {
                Circle().fill(Color.ckSurface)
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.ckTextSecondary)
            }
            .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search-cancel")
        .accessibilityLabel("Cancel search")
        .accessibilityHint("Double-tap to clear the search and return to the dock.")
        .accessibilityAddTraits(.isButton)
    }

    /// The merged capsule field spanning slots 2+3 — visually "the two circles
    /// merged". Autofocuses on appear; every keystroke filters the timeline live.
    private var searchField: some View {
        @Bindable var ui = ui
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.ckTextSecondary)
                .accessibilityHidden(true)
            TextField("Search your takes", text: $ui.searchQuery)
                .focused($searchFocused)
                .font(CatchlightFont.ui(.regular, size: 16, relativeTo: .body))
                .foregroundStyle(Color.ckTextPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("search-field")
                .accessibilityLabel("Search Takes")
                .accessibilityHint("Type to filter the timeline by text.")
        }
        .padding(.horizontal, 14)
        .frame(height: buttonSize)
        .background(Capsule().fill(Color.ckSurface))
        .onAppear { searchFocused = true }
    }

    /// Search (slot 4, SEARCHING) — dismisses the keyboard; the Return-key
    /// equivalent. The query (and live filtering) stays.
    private var searchDismissButton: some View {
        Button {
            searchFocused = false
        } label: {
            navIcon("magnifyingglass", active: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search-tab")
        .accessibilityLabel("Search")
        .accessibilityHint("Double-tap to dismiss the keyboard and review results.")
        .accessibilityAddTraits(.isButton)
    }

    /// The x of the Add button's centre within the dock's coordinate space, so the
    /// caller can terminate the spine there. With four equal columns + 12pt h-pad,
    /// the Add column centre is at one-eighth of the dock width (plus pad).
    static func addButtonCentreX(dockWidth: CGFloat) -> CGFloat {
        let usable = dockWidth - 24   // 12pt padding each side
        return 12 + usable / 8
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
