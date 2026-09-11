//
//  ReminderOrphanSweepTests.swift
//  CatchlightCoreTests
//
//  `sweepOrphanedRequests` — the only path that can cancel an alarm whose Take is gone.
//
//  🚨 Every other cancellation in the app starts from a Take that is still in the store, so
//  an orphan is unreachable by all of them. `rescheduleAll` clears identifiers derived from
//  the takes it is handed, which is exactly why an orphan survived every reschedule forever.
//  The owner met it through Start over: the wipe cleared the keychain, the defaults and the
//  store, and left the alarms still registered with iOS (2026-09-11).
//
//  What these guard is the two ways a sweep can be wrong, and the second is the dangerous one:
//  leaving an orphan behind, or deleting a live user's alarms.
//

// App-target only, matching `ReminderSchedulerTests` — `ReminderScheduler` lives in the
// iOS app target, so this is gated the same way.
#if canImport(Catchlight)
import XCTest
import UserNotifications
@testable import Catchlight
@testable import CatchlightCore

private final class PendingCenter: NotificationScheduling {
    var pending: [String] = []
    private(set) var removedPending: [String] = []
    private(set) var removedDelivered: [String] = []

    func add(_ request: UNNotificationRequest) { pending.append(request.identifier) }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPending.append(contentsOf: identifiers)
        pending.removeAll { identifiers.contains($0) }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDelivered.append(contentsOf: identifiers)
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }

    func pendingIdentifiers() async -> [String] { pending }
}

final class ReminderOrphanSweepTests: XCTestCase {

    private var center: PendingCenter!
    private var scheduler: ReminderScheduler!

    private let live = UUID()
    private let dead = UUID()

    override func setUp() {
        super.setUp()
        center = PendingCenter()
        scheduler = ReminderScheduler(center: center)
    }

    override func tearDown() {
        center = nil
        scheduler = nil
        super.tearDown()
    }

    /// The reported fault: a Take is gone, its alarm is not.
    func testRemovesRequestsWhoseTakeIsGone() async {
        center.pending = [dead.uuidString]
        await scheduler.sweepOrphanedRequests(liveTakeIDs: [live])
        XCTAssertEqual(center.removedPending, [dead.uuidString])
        XCTAssertTrue(center.pending.isEmpty)
    }

    /// 🚨 The dangerous direction. A sweep that over-reaches silently cancels a live user's
    /// reminders, which is worse than the bug it fixes — they would never know.
    func testLeavesRequestsWhoseTakeStillExists() async {
        center.pending = [live.uuidString,
                          "\(live.uuidString)#0",
                          "\(live.uuidString)#snooze",
                          "\(live.uuidString)#loc",
                          "\(live.uuidString)#followup1"]
        let before = center.pending
        await scheduler.sweepOrphanedRequests(liveTakeIDs: [live])
        XCTAssertTrue(center.removedPending.isEmpty)
        XCTAssertEqual(center.pending, before)
    }

    /// Every suffix form the scheduler produces must be recognised as belonging to its base,
    /// or the sweep would spare an orphan's snooze while taking its alarm.
    func testSuffixedIdentifiersFollowTheirBase() async {
        center.pending = ["\(dead.uuidString)#0",
                          "\(dead.uuidString)#snooze",
                          "\(dead.uuidString)#today",
                          "\(dead.uuidString)#loc",
                          "\(dead.uuidString)#followup2"]
        await scheduler.sweepOrphanedRequests(liveTakeIDs: [live])
        XCTAssertEqual(Set(center.removedPending), Set([
            "\(dead.uuidString)#0", "\(dead.uuidString)#snooze", "\(dead.uuidString)#today",
            "\(dead.uuidString)#loc", "\(dead.uuidString)#followup2"
        ]))
    }

    /// Delivered banners go too. A notification already sitting in Notification Centre shows
    /// the Take's text just as a pending one will, and the Take is gone.
    func testAlsoClearsDeliveredNotifications() async {
        center.pending = [dead.uuidString]
        await scheduler.sweepOrphanedRequests(liveTakeIDs: [live])
        XCTAssertEqual(center.removedDelivered, [dead.uuidString])
    }

    /// ⚠️ Anything unparseable is LEFT ALONE. This deletes user-visible alarms, so a sweep
    /// that cannot name what it is removing must remove nothing — a future identifier scheme,
    /// or something another part of the app scheduled, is not this function's to bin.
    func testUnparseableIdentifiersAreUntouched() async {
        center.pending = ["not-a-uuid", "", "#snooze", "catchlight-housekeeping"]
        let before = center.pending
        await scheduler.sweepOrphanedRequests(liveTakeIDs: [live])
        XCTAssertTrue(center.removedPending.isEmpty)
        XCTAssertEqual(center.pending, before)
    }

    /// A wiped account: nothing live, everything pending is an orphan. The Start over case.
    func testEmptyLiveSetRemovesEveryTakeRequest() async {
        center.pending = [dead.uuidString, "\(live.uuidString)#0", UUID().uuidString]
        await scheduler.sweepOrphanedRequests(liveTakeIDs: [])
        XCTAssertTrue(center.pending.isEmpty)
    }

    /// A healthy install must cost nothing — no removal call at all, rather than an empty one.
    func testNoOrphansMeansNoRemovalCall() async {
        center.pending = [live.uuidString]
        await scheduler.sweepOrphanedRequests(liveTakeIDs: [live])
        XCTAssertTrue(center.removedPending.isEmpty)
        XCTAssertTrue(center.removedDelivered.isEmpty)
    }
}

#endif
