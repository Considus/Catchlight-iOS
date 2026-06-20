//
//  UIState.swift
//  Catchlight (iOS app target) — Phase 6 UI, one-surface dock redesign 2026-06-10
//
//  Cross-cutting, presentation-only UI coordination shared by RootView and its
//  children. The app has ONE surface — the timeline — and the bottom dock MORPHS
//  between three states (resting / filtering / searching) instead of switching
//  tabs. This class owns the dock mode, the live filter toggles, and the search
//  query, plus the petal fan / editor / settings / paywall / conflict / spotlight
//  presentation state. @Observable (iOS 17+). It owns NO domain data — the feature
//  view models do — so it stays a thin coordinator any screen can read via the
//  environment.
//
//  Filter toggle semantics (owner decision 2026-06-10):
//    • tap   = off ↔ on (plain). Tapping while ON — modified or not — turns OFF
//              and clears the modifier.
//    • long-press = on + modifier ("Done" for Tasks, "Expired" for Reminders).
//              Long-pressing while already modified returns to plain ON.
//    • Notes is mutually exclusive with Tasks/Reminders (a pure note can't also
//      be a task/reminder): turning Notes on clears the other two (and their
//      modifiers); turning Tasks or Reminders on clears Notes.
//    • All toggles off keeps the dock in FILTERING (unfiltered timeline) — the
//      user may be composing another combination. Exit is the timeline
//      background tap (DailiesView) or implicit via exitToResting().
//

import SwiftUI
import CatchlightCore

@Observable
final class UIState {

    /// The dock's three morph states. There are no separate screens — the
    /// timeline is always behind the dock; only the dock contents and the
    /// active timeline filter change.
    enum DockMode: Hashable { case resting, filtering, searching }

    var dockMode: DockMode = .resting

    // FILTERING-state toggles. Modifiers are meaningful only while their
    // parent toggle is on (the mutation funcs maintain that invariant).
    var filterNotes = false
    var filterTasks = false
    /// "Done" modifier — completed tasks only. Implies `filterTasks`.
    var filterTasksDone = false
    var filterReminders = false
    /// "Expired" modifier — reminder date already passed. Implies `filterReminders`.
    var filterRemindersExpired = false
    /// Important toggle (slot 1 in FILTERING, 2026-06-19). Orthogonal — composes
    /// with the type toggles and clears nothing (an Important Take can be any type).
    var filterImportant = false

    // SEARCHING-state live query. Every keystroke narrows the timeline.
    var searchQuery = ""

    /// Whether the search keyboard (and its docked search bar) is raised. The search
    /// field rides the keyboard as a UIKit `inputAccessoryView` (2026-06-20), so this
    /// gates that accessory. True on entering search; the magnifier / Return lowers it
    /// (keeping the query + results, the dock shows a tap-to-resume bar); tapping the
    /// dock bar raises it again. Only meaningful while `dockMode == .searching`.
    var searchKeyboardUp = false

    // Petal fan.
    var petalFanTake: Take?
    var petalFanOrigin: CGPoint = .zero
    var isPetalFanPresented: Bool { petalFanTake != nil }

    // Take editor — edit-in-place (the top-anchored overlay editor was retired in
    // Phase 3, 2026-06-17; all create/edit happens in the timeline now).

    /// In-place editing (edit-in-place redesign 2026-06-17). When set, the matching
    /// timeline row becomes the live editable Take *in position* while every other
    /// row + the chrome masks behind it — the "Iris-touch focus" applied to editing.
    /// The draft + focused-block state live in DailiesView; this is just the id of
    /// the Take under focus.
    var editingTakeID: UUID?
    var isEditingInPlace: Bool { editingTakeID != nil }

    /// A freshly-created blank Take handed to DailiesView to edit IN PLACE (Phase 2
    /// 2026-06-17). The dock's + sets this instead of opening the top-anchored
    /// overlay; DailiesView injects it into the timeline at the Order-appropriate end
    /// (Oldest→bottom, Newest→top), focuses it, and clears this. It is NOT persisted
    /// until the inline save (a blank one dismissed leaves nothing behind).
    var pendingInlineNewTake: Take?

    /// A petal-fan selection handed to the in-place editor, carrying the working
    /// activity-type set. Reshapes the editor's live block DRAFT — the Task Mark
    /// reshapes the on-screen blocks, never the stored copy — so a make-checklist
    /// toggle lands on what the user is typing, not a stale row. Carries a token so
    /// two identical selections in a row still trigger.
    struct EditorFanCommand: Equatable {
        let token: UUID
        let isNote: Bool
        let isTask: Bool
        let hasReminder: Bool
        /// The time chosen in the Reminder picker (nil when no Reminder).
        let reminderDate: Date?
        /// Model-C picker choices (owner 2026-06-18) — ignored when `hasReminder` is false.
        let reminderAlarm: Bool
        let reminderAllDay: Bool
        let isObie: Bool
    }

    /// The Focus-ring selection for the IN-PLACE editor (edit-in-place redesign
    /// 2026-06-17). When the Focus ring is opened from a Take being edited inline,
    /// its commit must reshape that editor's live draft — not the stored copy — so
    /// the selection (incl. an Obie change) rides the inline save instead of being
    /// silently reverted when the draft is written back. DailiesView consumes it.
    var inlineFanCommand: EditorFanCommand?

    /// Commit-in-progress hook, registered by DailiesView while it's on screen. Lets
    /// the app save a mid-edit Take through DailiesView's own save path from outside
    /// the view — specifically `AppModel.relock`, which must persist the draft BEFORE
    /// it tears down the store (owner 2026-06-17: phone-lock should auto-save a
    /// mid-edit Take, not discard it). nil when nothing is editing / DailiesView is gone.
    var commitInlineEdit: (() -> Void)?

    /// Settings sheet — a swipe UP on the dock toggles this once the first-run
    /// orientation has finished (step >= 4 in `FirstRunOrientationState`).
    /// (Owner redesign 2026-06-11 — replaces the long-press on Dailies.)
    var isSettingsPresented = false

    /// Sync-conflict resolution sheet — opened from the timeline's "Review" banner
    /// when `AppModel.conflictQueue.pending` is non-empty (Task 6.15).
    var isConflictSheetPresented = false

    /// Paywall sheet (Task 6.20). Surfaced post-onboarding when the user has no
    /// entitlement, on any create/edit attempt while lapsed, and from the
    /// Settings → Manage Subscription row. Not a hard gate — users can dismiss
    /// and continue using the app in read-only mode.
    var isPaywallPresented = false

    /// The Storyboard — a full-screen list of every task-bearing Take (owner 2026-06-19).
    /// Presented over the timeline; the entry point is still being decided, so for now
    /// it is opened from a DEBUG-only Settings row and closed by its own X.
    var isStoryboardPresented = false

    /// Task 6.19 — Spotlight deep-link target. Set by the app's
    /// `onContinueUserActivity` handler when a Take is tapped in Spotlight;
    /// DailiesView reads this to scroll-and-flash the matching row. The
    /// handler clears it after the highlight fires so a re-tap re-targets.
    var spotlightTargetTakeID: UUID?

    // MARK: - Dock mode transitions

    /// Enter FILTERING (the Sequence dock button). Toggles start from whatever
    /// they last were within this entry — entering always starts clean because
    /// exitToResting() is the only way back and it clears everything.
    func enterFiltering() {
        dockMode = .filtering
    }

    /// Enter SEARCHING (the Search dock button). The query starts empty and the
    /// keyboard (with the docked search bar) comes up.
    func enterSearching() {
        searchQuery = ""
        dockMode = .searching
        searchKeyboardUp = true
    }

    /// Lower the search keyboard but STAY in search — the query and filtered results
    /// remain, and the dock shows a tap-to-resume search bar (magnifier / Return).
    func lowerSearchKeyboard() { searchKeyboardUp = false }

    /// Raise the search keyboard again (tapping the dock's resumed search bar).
    func raiseSearchKeyboard() { searchKeyboardUp = true }

    /// Return the dock to RESTING and clear every filter/search input, so the
    /// timeline is unfiltered. Safe to call from any state (idempotent).
    func exitToResting() {
        dockMode = .resting
        filterNotes = false
        filterTasks = false
        filterTasksDone = false
        filterReminders = false
        filterRemindersExpired = false
        filterImportant = false
        searchQuery = ""
    }

    // MARK: - Filter toggle mutations (semantics documented in the header)

    /// Tap on the Important toggle: off ↔ on. Orthogonal to the type toggles, so
    /// it neither clears them nor is cleared by them (2026-06-19).
    func tapImportantFilter() {
        filterImportant.toggle()
    }

    /// Tap on the Notes toggle: off ↔ on. Turning ON clears Tasks/Reminders
    /// (and their modifiers) — a pure note can't also be a task/reminder.
    func tapNotesFilter() {
        if filterNotes {
            filterNotes = false
        } else {
            filterNotes = true
            filterTasks = false
            filterTasksDone = false
            filterReminders = false
            filterRemindersExpired = false
        }
    }

    /// Tap on the Tasks toggle: off ↔ on (plain). Tapping while ON — whether
    /// plain or Done-modified — turns OFF and clears the modifier.
    func tapTasksFilter() {
        if filterTasks {
            filterTasks = false
            filterTasksDone = false
        } else {
            filterTasks = true
            filterTasksDone = false
            filterNotes = false
        }
    }

    /// Long-press on the Tasks toggle: ON + "Done" modifier (from off or plain
    /// on). Long-pressing while already Done-modified returns to plain ON.
    func longPressTasksFilter() {
        if filterTasks && filterTasksDone {
            filterTasksDone = false           // back to plain on
        } else {
            filterTasks = true
            filterTasksDone = true
            filterNotes = false
        }
    }

    /// Tap on the Reminders toggle: off ↔ on (plain). Tapping while ON —
    /// whether plain or Expired-modified — turns OFF and clears the modifier.
    func tapRemindersFilter() {
        if filterReminders {
            filterReminders = false
            filterRemindersExpired = false
        } else {
            filterReminders = true
            filterRemindersExpired = false
            filterNotes = false
        }
    }

    /// Long-press on the Reminders toggle: ON + "Expired" modifier (from off
    /// or plain on). Long-pressing while already Expired-modified returns to
    /// plain ON.
    func longPressRemindersFilter() {
        if filterReminders && filterRemindersExpired {
            filterRemindersExpired = false    // back to plain on
        } else {
            filterReminders = true
            filterRemindersExpired = true
            filterNotes = false
        }
    }

    // MARK: - Live timeline filter

    /// The filter the current dock state describes — applied live by
    /// DailiesView. Empty (matches everything) in RESTING, built from the
    /// toggles in FILTERING, and from the typed query in SEARCHING. Matching
    /// is the pure `SequenceFilter.matches` with AND semantics.
    var activeTimelineFilter: SequenceFilter {
        switch dockMode {
        case .resting:
            return SequenceFilter()
        case .filtering:
            return SequenceFilter(
                requireTask: filterTasks,
                requireReminder: filterReminders,
                requireNoteOnly: filterNotes,
                requireCompleted: filterTasksDone,
                requireExpiredReminder: filterRemindersExpired,
                requireImportant: filterImportant
            )
        case .searching:
            return SequenceFilter(text: searchQuery)
        }
    }

    // MARK: - Petal fan / editor

    /// Animation for the surrounding-content fade when the petal fan appears or
    /// dismisses. Driven from the mutation site via `withAnimation` rather than a
    /// `.animation(_:value:)` view modifier, so the fade animates without coupling the
    /// views to a value-observing modifier (which tripped SwiftUI's type-checker).
    static let fanFade: Animation = .easeInOut(duration: 0.2)

    func openPetalFan(for take: Take, origin: CGPoint = .zero) {
        petalFanOrigin = origin
        withAnimation(Self.fanFade) { petalFanTake = take }
    }

    func closePetalFan() {
        withAnimation(Self.fanFade) { petalFanTake = nil }
    }

    /// Enter in-place editing on a timeline Take (edit-in-place redesign). The fade
    /// matches the petal fan's, so masking the surrounding timeline reads the same as
    /// the Iris-touch focus.
    func beginEditingInPlace(_ take: Take) {
        withAnimation(Self.fanFade) { editingTakeID = take.id }
    }

    func endEditingInPlace() {
        withAnimation(Self.fanFade) { editingTakeID = nil }
    }
}
