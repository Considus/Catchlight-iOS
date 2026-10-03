//
//  DockFilterStateTests.swift
//  CatchlightCoreTests — one-surface dock redesign (2026-06-10)
//
//  Pins the UIState dock logic: the morphing dock's mode transitions, the
//  filter-toggle cycle (tap = off ↔ on; long-press = on + modifier; tap while
//  modified = off), Notes ↔ Tasks/Reminders mutual exclusivity, the all-off
//  "stay in filtering" rule, exitToResting's full clear, and the state →
//  SequenceFilter mapping the timeline consumes.
//
//  UIState lives in the iOS app target, so this test is gated by
//  `#if canImport(Catchlight)` and runs inside the iOS test bundle. Under
//  `swift test` on macOS the Core tests run unchanged.
//

#if canImport(Catchlight)
import XCTest
import CatchlightCore
@testable import Catchlight

@MainActor
final class DockFilterStateTests: XCTestCase {

    // MARK: - Mode transitions

    func testEnterFilteringAndSearching_setModes_andExitClearsBack() {
        let ui = UIState()
        XCTAssertEqual(ui.dockMode, .resting)

        ui.enterFiltering()
        XCTAssertEqual(ui.dockMode, .filtering)

        ui.exitToResting()
        XCTAssertEqual(ui.dockMode, .resting)

        ui.enterSearching()
        XCTAssertEqual(ui.dockMode, .searching)
        XCTAssertEqual(ui.searchQuery, "")
    }

    /// All toggles off keeps the dock in FILTERING — no auto-exit; the user
    /// may be about to choose another combination.
    func testAllTogglesOff_staysInFiltering() {
        let ui = UIState()
        ui.enterFiltering()
        ui.tapTasksFilter()      // on
        ui.tapTasksFilter()      // off again — everything off now
        XCTAssertFalse(ui.filterTasks)
        XCTAssertFalse(ui.filterNotes)
        XCTAssertFalse(ui.filterReminders)
        XCTAssertEqual(ui.dockMode, .filtering, "All-off must NOT auto-exit filtering")
        XCTAssertTrue(ui.activeTimelineFilter.isEmpty, "All-off filtering shows the unfiltered timeline")
    }

    // MARK: - Notes exclusivity (both directions)

    func testNotesOn_clearsTasksAndRemindersAndTheirModifiers() {
        let ui = UIState()
        ui.enterFiltering()
        ui.longPressTasksFilter()       // tasks on + Done
        ui.longPressRemindersFilter()   // reminders on + Expired

        ui.tapNotesFilter()
        XCTAssertTrue(ui.filterNotes)
        XCTAssertFalse(ui.filterTasks)
        XCTAssertFalse(ui.filterTasksDone)
        XCTAssertFalse(ui.filterReminders)
        XCTAssertFalse(ui.filterRemindersExpired)
    }

    func testTasksOrRemindersOn_clearNotes() {
        let ui = UIState()
        ui.enterFiltering()

        ui.tapNotesFilter()
        ui.tapTasksFilter()
        XCTAssertFalse(ui.filterNotes, "Tasks on must clear Notes")
        XCTAssertTrue(ui.filterTasks)

        ui.tapTasksFilter()             // off
        ui.tapNotesFilter()
        ui.tapRemindersFilter()
        XCTAssertFalse(ui.filterNotes, "Reminders on must clear Notes")
        XCTAssertTrue(ui.filterReminders)

        // Long-press paths clear Notes too.
        ui.tapRemindersFilter()         // off
        ui.tapNotesFilter()
        ui.longPressTasksFilter()
        XCTAssertFalse(ui.filterNotes, "Long-press Tasks must clear Notes")
    }

    // MARK: - Modifier cycle

    /// Tap = off ↔ on (plain). Long-press = on + modifier. Tap while modified
    /// = off (modifier cleared). Long-press while modified = back to plain on.
    func testTasksToggleCycle() {
        let ui = UIState()
        ui.enterFiltering()

        // Long-press from off: on + Done.
        ui.longPressTasksFilter()
        XCTAssertTrue(ui.filterTasks)
        XCTAssertTrue(ui.filterTasksDone)

        // Tap while modified: off, modifier cleared.
        ui.tapTasksFilter()
        XCTAssertFalse(ui.filterTasks)
        XCTAssertFalse(ui.filterTasksDone)

        // Tap from off: plain on.
        ui.tapTasksFilter()
        XCTAssertTrue(ui.filterTasks)
        XCTAssertFalse(ui.filterTasksDone)

        // Long-press while plain on: adds the modifier.
        ui.longPressTasksFilter()
        XCTAssertTrue(ui.filterTasks)
        XCTAssertTrue(ui.filterTasksDone)

        // Long-press while modified: back to plain on.
        ui.longPressTasksFilter()
        XCTAssertTrue(ui.filterTasks)
        XCTAssertFalse(ui.filterTasksDone)
    }

    func testRemindersToggleCycle() {
        let ui = UIState()
        ui.enterFiltering()

        ui.longPressRemindersFilter()
        XCTAssertTrue(ui.filterReminders)
        XCTAssertTrue(ui.filterRemindersExpired)

        ui.tapRemindersFilter()
        XCTAssertFalse(ui.filterReminders)
        XCTAssertFalse(ui.filterRemindersExpired)

        ui.tapRemindersFilter()
        XCTAssertTrue(ui.filterReminders)
        XCTAssertFalse(ui.filterRemindersExpired)

        ui.longPressRemindersFilter()
        XCTAssertTrue(ui.filterRemindersExpired)

        ui.longPressRemindersFilter()
        XCTAssertTrue(ui.filterReminders)
        XCTAssertFalse(ui.filterRemindersExpired)
    }

    // MARK: - exitToResting clears everything

    func testExitToResting_clearsAllTogglesModifiersAndQuery() {
        let ui = UIState()
        ui.enterFiltering()
        ui.longPressTasksFilter()
        ui.longPressRemindersFilter()
        ui.searchQuery = "leftover"

        ui.exitToResting()
        XCTAssertEqual(ui.dockMode, .resting)
        XCTAssertFalse(ui.filterNotes)
        XCTAssertFalse(ui.filterTasks)
        XCTAssertFalse(ui.filterTasksDone)
        XCTAssertFalse(ui.filterReminders)
        XCTAssertFalse(ui.filterRemindersExpired)
        XCTAssertEqual(ui.searchQuery, "")
        XCTAssertTrue(ui.activeTimelineFilter.isEmpty)
    }

    /// exitToResting also lowers the search keyboard flag — leaving it raised let the
    /// KeyboardSearchBar reconcile fight the keyboard (owner 2026-06-22 bug).
    func testExitToResting_lowersSearchKeyboardFlag() {
        let ui = UIState()
        ui.enterSearching()
        XCTAssertTrue(ui.searchKeyboardUp)

        ui.exitToResting()
        XCTAssertFalse(ui.searchKeyboardUp)
    }

    /// Opening a Take to edit while searching exits search first, so the editor's
    /// keyboard toolbar and the search bar never contend (owner 2026-06-22 bug).
    func testBeginEditingInPlace_whileSearching_exitsSearch() {
        let ui = UIState()
        ui.enterSearching()
        XCTAssertEqual(ui.dockMode, .searching)
        XCTAssertTrue(ui.searchKeyboardUp)

        let take = Take(createdAt: Date(), modifiedAt: Date(),
                        blocks: [.textLine("find me")], isNote: true)
        ui.beginEditingInPlace(take)

        XCTAssertEqual(ui.dockMode, .resting, "search must be exited before editing")
        XCTAssertFalse(ui.searchKeyboardUp)
        XCTAssertEqual(ui.editingTakeID, take.id)
    }

    // MARK: - State → SequenceFilter mapping

    func testActiveTimelineFilter_mapsDockStateToSequenceFilter() {
        let ui = UIState()

        // RESTING: always empty, regardless of stale toggle values.
        XCTAssertTrue(ui.activeTimelineFilter.isEmpty)

        // FILTERING: toggles map to their require* counterparts.
        ui.enterFiltering()
        ui.tapNotesFilter()
        XCTAssertEqual(ui.activeTimelineFilter, SequenceFilter(requireNoteOnly: true))

        ui.longPressTasksFilter()    // clears Notes, sets task + Done
        XCTAssertEqual(ui.activeTimelineFilter,
                       SequenceFilter(requireTask: true, requireCompleted: true))

        ui.longPressRemindersFilter()
        XCTAssertEqual(ui.activeTimelineFilter,
                       SequenceFilter(requireTask: true,
                                      requireReminder: true,
                                      requireCompleted: true,
                                      requireExpiredReminder: true))

        // SEARCHING: only the typed text filters; toggles are not in play.
        ui.exitToResting()
        ui.enterSearching()
        ui.searchQuery = "framer"
        XCTAssertEqual(ui.activeTimelineFilter, SequenceFilter(text: "framer"))
    }
}
#endif
