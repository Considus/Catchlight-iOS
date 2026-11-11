//
//  DailiesToolbar.swift
//  Catchlight (iOS app target)
//
//  The toolbar at the bottom of Dailies, as drawn in the redesign (the app screens
//  drawing, "Search and Sequence"):
//  one flat panel of four labelled icons, Add, Storyboard, Sequence and Search. Add's
//  icon sits in a square filled with the action colour (Mark, 2026-11-10).
//
//  The toolbar has three modes (`UIState.ToolbarMode`):
//
//    RESTING:   the panel. Add creates a Take and opens the editor. Storyboard opens
//               the Storyboard. Sequence opens the filters. Search opens search.
//    FILTERING: the panel stays, and a row of four filter chips sits above it:
//               Important, Notes, Tasks and Reminders. Tap = off or on; a long press
//               on Tasks or Reminders turns on "completed only" or "expired only",
//               shown by the chip's swapped icon. Notes excludes the other two types.
//               Leaving: tap Sequence again, or tap empty timeline (DailiesView).
//    SEARCHING: with the keyboard up, the search row rides the keyboard
//               (`KeyboardSearchBar`) and this view draws nothing. With the keyboard
//               lowered, the panel holds the same row: the query (tap to type again)
//               and Cancel, which leaves search and clears the query.
//
//  Settings: swipe up on the panel. It is not a screen-edge swipe, so it never fights
//  the system home gesture, and VoiceOver gets an explicit "Open Settings" action on
//  the Storyboard button.
//
//  The panel is opaque, flat and outlined with the `line` token, 12pt in from each
//  side. Nothing fades behind it.
//
//  Long-press pattern: Button + .simultaneousGesture(LongPressGesture). Do NOT switch
//  to .onLongPressGesture: synthesized presses on the simulator never reach it.
//  Because the Button's tap action also fires on finger-up after a long press, each
//  long-pressable chip swallows the one tap that follows.
//

import SwiftUI
import CatchlightCore

struct DailiesToolbar: View {
    @Environment(UIState.self) private var ui
    /// The home-indicator inset alone, never counting the keyboard (CatchlightApp).
    @Environment(\.homeIndicatorInset) private var homeIndicatorInset

    /// Create a Take and open the editor (gated by the paywall in RootView).
    var onNewTake: () -> Void

    /// One-shot guards: a long press on a chip also delivers the Button tap on
    /// finger-up; these swallow that single trailing tap.
    @State private var suppressTasksTap = false
    @State private var suppressRemindersTap = false

    var body: some View {
        VStack(spacing: DailiesToolbarMetrics.chipGap) {
            if ui.toolbarMode == .filtering {
                filterChips
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if ui.toolbarMode == .searching && ui.searchKeyboardUp {
                // The search row rides the keyboard (KeyboardSearchBar). Draw nothing,
                // so there is never a second `search-field` or `search-cancel`.
                Color.clear.frame(height: CatchlightLayout.dockHeight)
            } else {
                panel
            }
        }
        .animation(.easeInOut(duration: 0.2), value: ui.toolbarMode)
        // At the dock's place, measured from the home-indicator inset alone, which never
        // counts the keyboard, so the panel can't stop high while the search keyboard and its
        // bar go away.
        .atDockPlace(homeIndicatorInset: homeIndicatorInset)
        // The soft edge the Takes fade into behind and below the panel, as the old toolbar
        // had (owner 2026-11-10: "lost its fade and mask below the bottom menu"). It starts a
        // little above the panel so a Take dissolves before it reaches it. A Take still showing
        // through it keeps its taps.
        .padding(.top, DailiesToolbarMetrics.fadeAbove)
        .dockFadeBackground(passesTouches: true)
        .onChange(of: ui.toolbarMode) { old, mode in
            // The chips appear and go without moving focus, so say so.
            let announcement: String
            switch mode {
            case .filtering: announcement = String(localized: "Filters shown above the toolbar.")
            case .searching: announcement = String(localized: "Search your Takes")
            case .resting:
                guard old != .resting else { return }
                announcement = String(localized: "Showing all Takes.")
            }
            UIAccessibility.post(notification: .layoutChanged, argument: announcement)
        }
    }

    // MARK: - Panel

    private var panel: some View {
        Group {
            if ui.toolbarMode == .searching {
                searchRow
            } else {
                HStack(spacing: 0) {
                    addButton
                    storyboardButton
                    sequenceButton
                    searchButton
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: CatchlightLayout.dockHeight)
        .flatEdgePanel(fill: Color.ckPanel)
        // Settings: swipe up on the panel. The gesture belongs to the panel alone, so a
        // flick that starts in the home-indicator strip below it never reaches it
        // (owner 2026-06-23: home-swiping between captures latched Settings open).
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard value.translation.height < -30,
                          abs(value.translation.width) < 60 else { return }
                    ui.isSettingsPresented = true
                }
        )
    }

    /// One labelled column of the panel: the icon over its label, a quarter of the width.
    private func toolbarItem(icon: some View, label: LocalizedStringKey) -> some View {
        VStack(spacing: 3) {
            icon.frame(height: DailiesToolbarMetrics.addSquare)
            Text(label)
                .ckBody(.medium, size: 11, relativeTo: .caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                // Like the system tab bar: the label stops growing at the second size
                // above the default, and a long press shows it large instead.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        // Each column fills the panel's full height, so a tap anywhere in it counts.
        .frame(maxWidth: .infinity, minHeight: CatchlightLayout.dockHeight)
        .contentShape(Rectangle())
        .accessibilityShowsLargeContentViewer {
            icon
            Text(label)
        }
    }

    private func panelIcon(_ glyph: ToolbarGlyph) -> some View {
        glyph.stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            .frame(width: DailiesToolbarMetrics.iconSize, height: DailiesToolbarMetrics.iconSize)
    }

    private var addButton: some View {
        Button {
            onNewTake()
        } label: {
            toolbarItem(
                icon: ToolbarGlyph.plus
                    .stroke(Color.ckOnAccent, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                    .frame(width: DailiesToolbarMetrics.iconSize, height: DailiesToolbarMetrics.iconSize)
                    .frame(width: DailiesToolbarMetrics.addSquare, height: DailiesToolbarMetrics.addSquare)
                    .background(CatchlightShape.control.fill(Color.ckAdd)),
                label: "Add")
            .foregroundStyle(Color.ckTextPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("add-button")
        .accessibilityLabel("Add Take")
        .accessibilityHint("Double-tap to capture a new Take.")
        .accessibilityAddTraits(.isButton)
    }

    /// Storyboard: every Take with a task, full screen. VoiceOver's route to Settings
    /// lives here too, because the swipe is a gesture VoiceOver keeps for itself.
    private var storyboardButton: some View {
        Button {
            ui.isStoryboardPresented = true
        } label: {
            toolbarItem(icon: panelIcon(.storyboard), label: "Storyboard")
                .foregroundStyle(Color.ckTextSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("angle-tab")
        .accessibilityLabel("Storyboard")
        .accessibilityHint("Opens the Storyboard: every Take with a task. Use the actions rotor to open Settings.")
        .accessibilityAction(named: "Open Settings") {
            ui.isSettingsPresented = true
        }
        .accessibilityAddTraits(.isButton)
    }

    /// Sequence: opens the filter chips, and closes them again while they are open.
    private var sequenceButton: some View {
        let open = ui.toolbarMode == .filtering
        return Button {
            if open { ui.exitToResting() } else { ui.enterFiltering() }
        } label: {
            toolbarItem(icon: panelIcon(.sequence), label: "Sequence")
                .foregroundStyle(open ? Color.ckAccent : Color.ckTextSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sequence-tab")
        .accessibilityLabel("Sequence")
        .accessibilityHint(open
            ? "Double-tap to close the filters and show all Takes."
            : "Double-tap to filter the timeline by notes, tasks, or reminders.")
        .accessibilityAddTraits(open ? [.isSelected, .isButton] : [.isButton])
    }

    private var searchButton: some View {
        Button {
            // The keyboard comes up with the search row riding it (KeyboardSearchBar).
            ui.enterSearching()
        } label: {
            toolbarItem(icon: panelIcon(.search), label: "Search")
                .foregroundStyle(Color.ckTextSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search-tab")
        .accessibilityLabel("Search")
        .accessibilityHint("Double-tap to search your Takes.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Search row (keyboard lowered)

    /// Searching with the keyboard lowered: the query stays and the results stay
    /// browsable. The field brings the keyboard back; Cancel leaves search.
    private var searchRow: some View {
        HStack(spacing: 10) {
            Button {
                ui.raiseSearchKeyboard()
            } label: {
                HStack(spacing: 8) {
                    ToolbarGlyph.search
                        .stroke(Color.ckTextSecondary, style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
                        .frame(width: 17, height: 17)
                    Text(ui.searchQuery.isEmpty ? String(localized: "Search your Takes") : ui.searchQuery)
                        .ckBody(.regular, size: 15, relativeTo: .body)
                        .foregroundStyle(ui.searchQuery.isEmpty ? Color.ckTextSecondary : Color.ckTextPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: CatchlightLayout.minTouchTarget)
                .flatField()
                .contentShape(CatchlightShape.surface)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search-resume")
            .accessibilityLabel("Search Takes")
            .accessibilityValue(ui.searchQuery)
            .accessibilityHint("Double-tap to resume typing your search.")

            Button {
                ui.exitToResting()
            } label: {
                Text("Cancel")
                    .ckBody(.medium, size: 15, relativeTo: .body)
                    .foregroundStyle(Color.ckAccent)
                    .frame(minWidth: CatchlightLayout.minTouchTarget, minHeight: CatchlightLayout.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search-cancel")
            .accessibilityLabel("Cancel search")
            .accessibilityHint("Double-tap to clear the search and show all Takes.")
        }
        .padding(.horizontal, DailiesToolbarMetrics.searchRowInset)
    }

    // MARK: - Filter chips

    /// How a chip shows its state: off is the panel colour; on is the action colour;
    /// a long-press variant is on with its icon swapped.
    private enum ChipState { case off, on, variant }

    private var filterChips: some View {
        HStack(spacing: DailiesToolbarMetrics.chipSpacing) {
            importantChip
            notesChip
            tasksChip
            remindersChip
        }
    }

    /// Icon only (owner 2026-11-10: names beside the icons overflowed at large text sizes).
    /// The name stays as the VoiceOver label on each chip, and a long press at the large
    /// accessibility sizes shows icon and name in the large content viewer.
    private func chipFace(icon: some View, label: LocalizedStringKey, state: ChipState) -> some View {
        let on = state != .off
        return icon
            .frame(width: DailiesToolbarMetrics.chipIconSize, height: DailiesToolbarMetrics.chipIconSize)
            .foregroundStyle(on ? Color.ckOnAccent : Color.ckTextPrimary)
            .frame(maxWidth: .infinity, minHeight: CatchlightLayout.minTouchTarget)
            .background(CatchlightShape.control.fill(on ? Color.ckAdd : Color.ckPanel))
            .overlay(CatchlightShape.control.strokeBorder(on ? Color.ckAdd : Color.ckLine, lineWidth: 1))
            .contentShape(CatchlightShape.control)
            .accessibilityShowsLargeContentViewer {
                icon
                Text(label)
            }
    }

    private func chipIcon(_ glyph: ToolbarGlyph) -> some View {
        glyph.stroke(style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
    }

    /// Important: orthogonal to the type chips, so it neither clears them nor is cleared.
    private var importantChip: some View {
        Button {
            ui.tapImportantFilter()
        } label: {
            chipFace(icon: chipIcon(.important), label: "Important", state: ui.filterImportant ? .on : .off)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filter-important")
        .accessibilityLabel("Important filter")
        .accessibilityValue(ui.filterImportant ? "on" : "off")
        .accessibilityHint("Double-tap to show only Important Takes.")
        .accessibilityAddTraits(ui.filterImportant ? [.isSelected, .isButton] : [.isButton])
    }

    /// Notes: plain on or off, and turning it on clears Tasks and Reminders.
    private var notesChip: some View {
        Button {
            ui.tapNotesFilter()
        } label: {
            chipFace(icon: chipIcon(.note), label: "Notes", state: ui.filterNotes ? .on : .off)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filter-notes")
        .accessibilityLabel("Notes filter")
        .accessibilityValue(ui.filterNotes ? "on" : "off")
        .accessibilityHint("Double-tap to show only pure notes. Turning notes on clears the tasks and reminders filters.")
        .accessibilityAddTraits(ui.filterNotes ? [.isSelected, .isButton] : [.isButton])
    }

    /// Tasks: a tap toggles; a long press shows completed tasks only.
    private var tasksChip: some View {
        let state: ChipState = ui.filterTasksDone ? .variant : (ui.filterTasks ? .on : .off)
        return Button {
            if suppressTasksTap { suppressTasksTap = false; return }
            ui.tapTasksFilter()
        } label: {
            chipFace(icon: Group {
                if state == .variant {
                    Image(systemName: "checkmark.circle").font(.system(size: 18, weight: .medium))
                } else {
                    chipIcon(.task)
                }
            }, label: "Tasks", state: state)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                suppressTasksTap = true
                ui.longPressTasksFilter()
            }
        )
        .accessibilityIdentifier("filter-tasks")
        .accessibilityLabel("Tasks filter")
        .accessibilityValue(ui.filterTasksDone ? "done only" : (ui.filterTasks ? "on" : "off"))
        // The hint names the route VoiceOver can take (the named action, via the
        // rotor); the long press is a gesture VoiceOver keeps for itself.
        .accessibilityHint("Double-tap to toggle. Use the actions rotor for completed tasks only.")
        .accessibilityAction(named: "Completed tasks only") { ui.longPressTasksFilter() }
        .accessibilityAddTraits(ui.filterTasks ? [.isSelected, .isButton] : [.isButton])
    }

    /// Reminders: a tap toggles; a long press shows reminders whose time has passed.
    private var remindersChip: some View {
        let state: ChipState = ui.filterRemindersExpired ? .variant : (ui.filterReminders ? .on : .off)
        return Button {
            if suppressRemindersTap { suppressRemindersTap = false; return }
            ui.tapRemindersFilter()
        } label: {
            chipFace(icon: Group {
                if state == .variant {
                    Image(systemName: "clock.badge.exclamationmark").font(.system(size: 18, weight: .medium))
                } else {
                    chipIcon(.clock)
                }
            }, label: "Reminders", state: state)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                suppressRemindersTap = true
                ui.longPressRemindersFilter()
            }
        )
        .accessibilityIdentifier("filter-reminders")
        .accessibilityLabel("Reminders filter")
        .accessibilityValue(ui.filterRemindersExpired ? "expired only" : (ui.filterReminders ? "on" : "off"))
        .accessibilityHint("Double-tap to toggle. Use the actions rotor for expired reminders only.")
        .accessibilityAction(named: "Expired reminders only") { ui.longPressRemindersFilter() }
        .accessibilityAddTraits(ui.filterReminders ? [.isSelected, .isButton] : [.isButton])
    }
}

/// The toolbar's sizes, shared with the timeline's bottom clearance.
enum DailiesToolbarMetrics {
    /// The filled square behind Add's icon; every column's icon slot is this tall.
    static let addSquare: CGFloat = 34
    static let iconSize: CGFloat = 22
    /// Between the filter chips and the panel.
    static let chipGap: CGFloat = 8
    /// Between two filter chips.
    static let chipSpacing: CGFloat = 6
    /// A filter chip's icon, now that the chips carry no name beside it.
    static let chipIconSize: CGFloat = 20
    /// How far above the panel (or the chips) the fade behind the toolbar begins.
    static let fadeAbove: CGFloat = 16
    /// The search row's inset inside the panel.
    static let searchRowInset: CGFloat = 10
    /// The filter chip row: its 44pt height and the gap under it.
    static let chipRowClearance: CGFloat = CatchlightLayout.minTouchTarget + chipGap
}

/// The toolbar's and chips' icons, drawn from the app screens drawing's paths on a
/// 24-point grid and scaled to their frame. Stroked by the caller.
enum ToolbarGlyph: Shape {
    case plus, storyboard, sequence, search, important, note, task, clock

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * s, oy = rect.midY - 12 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        func line(_ path: inout Path, _ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) {
            path.move(to: p(a.0, a.1)); path.addLine(to: p(b.0, b.1))
        }
        var path = Path()
        switch self {
        case .plus:
            line(&path, (12, 6), (12, 18)); line(&path, (6, 12), (18, 12))
        case .storyboard:
            for (x, y) in [(4.5, 4.5), (13.5, 4.5), (4.5, 13.5), (13.5, 13.5)] as [(CGFloat, CGFloat)] {
                path.addRect(CGRect(x: ox + x * s, y: oy + y * s, width: 6 * s, height: 6 * s))
            }
        case .sequence:
            line(&path, (5, 7), (19, 7)); line(&path, (5, 12), (19, 12)); line(&path, (5, 17), (14, 17))
        case .search:
            path.addEllipse(in: CGRect(x: ox + 5 * s, y: oy + 5 * s, width: 12 * s, height: 12 * s))
            line(&path, (16, 16), (20, 20))
        case .important:
            line(&path, (12, 5), (12, 14.5)); line(&path, (12, 18.6), (12, 19))
        case .note:
            line(&path, (6, 8), (18, 8)); line(&path, (6, 12), (18, 12)); line(&path, (6, 16), (14, 16))
        case .task:
            path.move(to: p(5, 12.6)); path.addLine(to: p(9.4, 17)); path.addLine(to: p(19, 7.4))
        case .clock:
            path.addEllipse(in: CGRect(x: ox + 5 * s, y: oy + 5 * s, width: 14 * s, height: 14 * s))
            path.move(to: p(12, 8.5)); path.addLine(to: p(12, 12)); path.addLine(to: p(14.6, 13.4))
        }
        return path
    }
}

#Preview("Toolbar, resting (Night)") {
    VStack {
        Spacer()
        DailiesToolbar(onNewTake: {})
            .environment(UIState())
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}

#Preview("Toolbar, filtering") {
    let ui = UIState()
    ui.enterFiltering()
    ui.filterTasks = true
    ui.filterRemindersExpired = true
    ui.filterReminders = true
    return VStack {
        Spacer()
        DailiesToolbar(onNewTake: {})
            .environment(ui)
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}

#Preview("Toolbar, searching with the keyboard lowered") {
    let ui = UIState()
    ui.enterSearching()
    ui.lowerSearchKeyboard()
    return VStack {
        Spacer()
        DailiesToolbar(onNewTake: {})
            .environment(ui)
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.light)
}
