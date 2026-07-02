//
//  PendingReminderActionsTests.swift
//  CatchlightTests (app module) — 2026-07-01 mid-point review remediation
//
//  First coverage for the locked-Dismiss deferred-apply queue. The queue is a
//  plain string set in the app-group defaults; entries are bare UUID strings for
//  a TIME dismissal and `<uuid>#loc` for a LOCATION dismissal (a Take can carry
//  both a "when" and a "where" — dismissing one must not silence the other).
//  Bare-UUID entries are also the pre-2026-07 wire format, so already-queued
//  dismissals from an older build still drain.
//
//  iOS-only — gated on `canImport(Catchlight)`. The simulator does not enforce
//  app-group entitlements, so the suite defaults are read/writable in tests.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

final class PendingReminderActionsTests: XCTestCase {

    private var defaults: UserDefaults!
    private let key = "ckPendingDismissedIDs"

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: AppGroup.identifier),
                                 "app-group defaults must be constructible in the test host")
        defaults.removeObject(forKey: key)
    }

    override func tearDown() {
        defaults.removeObject(forKey: key)
        defaults = nil
        super.tearDown()
    }

    func testEnqueueAndDrain_timeDismissal() {
        let id = UUID()
        PendingReminderActions.enqueueDismiss(takeID: id.uuidString)
        let drained = PendingReminderActions.drainDismissed()
        XCTAssertEqual(drained, [.init(id: id, isLocation: false)])
        XCTAssertTrue(PendingReminderActions.drainDismissed().isEmpty,
                      "draining must clear the queue — each action resolves exactly once")
    }

    func testEnqueueAndDrain_locationDismissal() {
        let id = UUID()
        PendingReminderActions.enqueueDismiss(takeID: id.uuidString, isLocation: true)
        XCTAssertEqual(PendingReminderActions.drainDismissed(),
                       [.init(id: id, isLocation: true)])
    }

    func testDrain_bothKindsForTheSameTake_yieldsBoth() {
        // A Take with a "when" AND a "where": both dismissed while locked.
        let id = UUID()
        PendingReminderActions.enqueueDismiss(takeID: id.uuidString)
        PendingReminderActions.enqueueDismiss(takeID: id.uuidString, isLocation: true)
        let drained = Set(PendingReminderActions.drainDismissed().map(\.isLocation))
        XCTAssertEqual(drained, [false, true])
    }

    func testDrain_dropsJunkEntries_andReadsLegacyBareUUIDs() {
        let id = UUID()
        // Simulate an older build's bare-UUID entry plus junk alongside it.
        defaults.set([id.uuidString, "not-a-uuid", "also#loc"], forKey: key)
        XCTAssertEqual(PendingReminderActions.drainDismissed(),
                       [.init(id: id, isLocation: false)])
    }

    func testEnqueue_isDeduplicated() {
        let id = UUID()
        PendingReminderActions.enqueueDismiss(takeID: id.uuidString)
        PendingReminderActions.enqueueDismiss(takeID: id.uuidString)
        XCTAssertEqual(PendingReminderActions.drainDismissed().count, 1)
    }
}
#endif
