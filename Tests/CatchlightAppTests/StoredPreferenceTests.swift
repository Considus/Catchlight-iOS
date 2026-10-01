//
//  StoredPreferenceTests.swift
//  CatchlightAppTests
//
//  The Settings readers outside a view (`StoredPreference.current(_:)` and
//  `FollowUpReminders.isEnabled(_:)`) read the defaults they are handed. Each test uses
//  its own suite, so none of them touches the simulator's real Settings.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

final class StoredPreferenceTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "catchlight.tests.preferences.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testUnsetKeyReadsTheDefault() {
        XCTAssertEqual(SettingsViewModel.SyncMode.current(defaults), .auto)
        XCTAssertEqual(SettingsViewModel.AutoCleanup.current(defaults), .never)
        XCTAssertEqual(SettingsViewModel.SnoozeDuration.current(defaults), .oneHour)
        XCTAssertEqual(SettingsViewModel.DefaultReminderHours.current(defaults), .twentyFour)
    }

    func testStoredValueIsReadFromTheSuiteItIsHanded() {
        defaults.set("manual", forKey: "catchlight.syncMode")
        defaults.set("weekly", forKey: "catchlight.autoCleanup")
        defaults.set("fifteenMinutes", forKey: "catchlight.snoozeDuration")
        defaults.set("6", forKey: "catchlight.defaultReminderHours")

        XCTAssertEqual(SettingsViewModel.SyncMode.current(defaults), .manual)
        XCTAssertEqual(SettingsViewModel.AutoCleanup.current(defaults), .weekly)
        XCTAssertEqual(SettingsViewModel.SnoozeDuration.current(defaults), .fifteenMinutes)
        XCTAssertEqual(SettingsViewModel.DefaultReminderHours.current(defaults), .six)
    }

    /// A value this build does not recognise (a downgrade, or a corrupted entry) reads as
    /// the default rather than failing.
    func testUnrecognisedValueReadsTheDefault() {
        defaults.set("hourly", forKey: "catchlight.autoCleanup")
        defaults.set("", forKey: "catchlight.syncMode")

        XCTAssertEqual(SettingsViewModel.AutoCleanup.current(defaults), .never)
        XCTAssertEqual(SettingsViewModel.SyncMode.current(defaults), .auto)
    }

    func testFollowUpRemindersDefaultsOnAndReadsAStoredOff() {
        XCTAssertTrue(SettingsViewModel.FollowUpReminders.isEnabled(defaults),
                      "unset must read as ON, not as false")
        defaults.set(false, forKey: "catchlight.followUpReminders")
        XCTAssertFalse(SettingsViewModel.FollowUpReminders.isEnabled(defaults))
    }

    /// The keys are persisted: renaming one silently resets every user's choice.
    func testDefaultsKeysAreUnchanged() {
        XCTAssertEqual(SettingsViewModel.LockAfter.defaultsKey, "catchlight.lockAfter")
        XCTAssertEqual(SettingsViewModel.DefaultReminderHours.defaultsKey, "catchlight.defaultReminderHours")
        XCTAssertEqual(SettingsViewModel.SnoozeDuration.defaultsKey, "catchlight.snoozeDuration")
        XCTAssertEqual(SettingsViewModel.FollowUpReminders.defaultsKey, "catchlight.followUpReminders")
        XCTAssertEqual(SettingsViewModel.TakeSpacing.defaultsKey, "catchlight.takeSpacing")
        XCTAssertEqual(SettingsViewModel.TakeSort.defaultsKey, "catchlight.takeSort")
        XCTAssertEqual(SettingsViewModel.TimelineArrangement.defaultsKey, "catchlight.timelineArrangement")
        XCTAssertEqual(SettingsViewModel.CreationStamp.defaultsKey, "catchlight.creationStamp")
        XCTAssertEqual(SettingsViewModel.TakePreview.defaultsKey, "catchlight.takePreview")
        XCTAssertEqual(SettingsViewModel.AutoCleanup.defaultsKey, "catchlight.autoCleanup")
        XCTAssertEqual(SettingsViewModel.SyncMode.defaultsKey, "catchlight.syncMode")
    }
}
#endif
