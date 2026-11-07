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

    func testNoticeIsAUserFacingStorageNotice() {
        XCTAssertEqual(Notice.remindersSilenced.code.rawValue, 215)
        XCTAssertEqual(Notice.remindersSilenced.category, .storage)
    }
}
#endif
