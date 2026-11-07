//
//  RemindersSilencedTests.swift
//  CatchlightAppTests — the strip that says iOS notifications are off while a Take still has
//  a reminder set to alert. Before it, turning notifications off in iOS Settings silently
//  stopped every reminder, and only the diagnostics log recorded it.
//

#if canImport(Catchlight)
import XCTest
import UserNotifications
@testable import Catchlight
@testable import CatchlightCore

final class RemindersSilencedTests: XCTestCase {

    private func timed(alarm: Bool = true, done: Bool = false) -> Take {
        var reminder = TimeReminder(scheduledDate: Date(timeIntervalSince1970: 1_780_000_000),
                                    notificationIdentifier: UUID().uuidString)
        reminder.alarmEnabled = alarm
        reminder.isDone = done
        return Take(blocks: [.textLine("Call the framer")], timeReminder: reminder)
    }

    private func placed(alarm: Bool = true) -> Take {
        Take(blocks: [.textLine("Buy film")],
             locationReminder: LocationTrigger(latitude: 51.5, longitude: -0.1, radiusMetres: 150,
                                               triggerOnArrival: true, locationName: "Shop",
                                               alarmEnabled: alarm))
    }

    func testDenied_withATimeReminderSetToAlert_isSilenced() {
        XCTAssertTrue(ReminderScheduler.remindersSilenced(status: .denied, anyAlerting: ReminderScheduler.anyAlerting([timed()])))
    }

    func testDenied_withAPlaceReminderSetToAlert_isSilenced() {
        XCTAssertTrue(ReminderScheduler.remindersSilenced(status: .denied, anyAlerting: ReminderScheduler.anyAlerting([placed()])))
    }

    func testDenied_withOnlySilentDoneOrNoReminders_isNotSilenced() {
        let takes = [timed(alarm: false), timed(done: true), placed(alarm: false),
                     Take(blocks: [.textLine("No reminder")])]
        XCTAssertFalse(ReminderScheduler.remindersSilenced(status: .denied, anyAlerting: ReminderScheduler.anyAlerting(takes)))
    }

    /// Only a refusal silences: before the user is asked, the first reminder set asks them.
    func testAllowedOrNotYetAsked_isNotSilenced() {
        for status: UNAuthorizationStatus in [.authorized, .provisional, .ephemeral, .notDetermined] {
            XCTAssertFalse(ReminderScheduler.remindersSilenced(status: status, anyAlerting: ReminderScheduler.anyAlerting([timed()])), "\(status.rawValue)")
        }
    }

    // MARK: - Notice History onset (review on #365)

    @MainActor
    private func makeApp(locked: Bool, holding takes: [Take]) throws -> AppModel {
        let store = InMemoryTakeStore()
        for take in takes { try store.upsert(take) }
        return AppModel(needsOnboarding: false,
                        initialStore: locked ? InMemoryTakeStore() : store,
                        session: SessionController(),
                        makeStoreFromKeys: { _ in store },
                        unlockKeys: { KeyHierarchy(masterKeyBytes: Data(repeating: 7, count: 32)) },
                        lockState: locked ? .locked : .unlocked,
                        subscription: SubscriptionManager())
    }

    private func isolatedLog() throws -> (UserDefaults, DiagnosticsLog, () -> [String]) {
        let suite = "RemindersSilencedOnset.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let log = DiagnosticsLog(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("silenced-\(UUID().uuidString).json"))
        return (defaults, log, { log.entries().map(\.message).filter { $0.hasPrefix("[CCIOS-215]") } })
    }

    /// Activation reads `.denied` while the app is still locked, so nothing can be judged
    /// then. The unlock must record it, or Notice History misses a strip the user saw.
    @MainActor
    func testDeniedWhileLocked_isRecordedAtTheUnlock() async throws {
        let (defaults, log, lines) = try isolatedLog()
        let app = try makeApp(locked: true, holding: [timed()])
        app.notificationStatus = .denied
        app.refreshRemindersSilencedOnset(defaults: defaults, log: log)
        XCTAssertEqual(lines().count, 0, "nothing to judge while locked")

        await app.attemptUnlock()
        app.refreshRemindersSilencedOnset(defaults: defaults, log: log)
        XCTAssertEqual(lines().count, 1)
    }

    /// A reminder turned on while notifications are already off raises the strip at once, and
    /// the entry with it.
    @MainActor
    func testFirstAlertingReminderWhileDenied_isRecorded() throws {
        let (defaults, log, lines) = try isolatedLog()
        let app = try makeApp(locked: false, holding: [Take(blocks: [.textLine("No reminder")])])
        app.notificationStatus = .denied
        app.refreshRemindersSilencedOnset(defaults: defaults, log: log)
        XCTAssertEqual(lines().count, 0)

        XCTAssertTrue(app.dailiesVM.save(timed()))
        app.refreshRemindersSilencedOnset(defaults: defaults, log: log)
        XCTAssertEqual(lines().count, 1)
    }

    /// The onset belongs to the refusal, not to the reminders: a timeline that has no alerting
    /// reminder for a moment (the last one deleted, or the store swapped out while locking)
    /// doesn't end it, or the strip would be recorded again each time it came back.
    @MainActor
    func testNoAlertingReminderForAMoment_doesNotRecordItAgain() throws {
        let (defaults, log, lines) = try isolatedLog()
        let first = timed()
        let app = try makeApp(locked: false, holding: [first])
        app.notificationStatus = .denied
        app.refreshRemindersSilencedOnset(defaults: defaults, log: log)

        app.dailiesVM.delete(first)
        XCTAssertFalse(app.dailiesVM.anyAlertingReminder)
        app.refreshRemindersSilencedOnset(defaults: defaults, log: log)
        XCTAssertTrue(app.dailiesVM.save(timed()))
        app.refreshRemindersSilencedOnset(defaults: defaults, log: log)
        XCTAssertEqual(lines().count, 1)
    }

    /// Turning notifications back on ends the onset, so a later refusal is recorded again.
    @MainActor
    func testAllowedAgain_endsTheOnset() throws {
        let (defaults, log, lines) = try isolatedLog()
        let app = try makeApp(locked: false, holding: [timed()])
        app.notificationStatus = .denied
        app.refreshRemindersSilencedOnset(defaults: defaults, log: log)
        app.notificationStatus = .authorized
        app.refreshRemindersSilencedOnset(defaults: defaults, log: log)
        app.notificationStatus = .denied
        app.refreshRemindersSilencedOnset(defaults: defaults, log: log)
        XCTAssertEqual(lines().count, 2)
    }

    func testNoticeIsAUserFacingStorageNotice() {
        XCTAssertEqual(Notice.remindersSilenced.code.rawValue, 215)
        XCTAssertEqual(Notice.remindersSilenced.category, .storage)
    }
}
#endif
