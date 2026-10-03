//
//  ForegroundSyncTriggerTests.swift
//  CatchlightCoreTests — foreground sync triggers (2026-06-10)
//
//  The `.userPresence` master key cannot be unwrapped by a cold background
//  task, so foreground triggers (app became active / entering background) are
//  the primary sync path on hardware. The activation trigger is throttled
//  because `.inactive → .active` also fires for Face ID sheets, Notification
//  Centre pulls, and the app switcher — this suite pins the pure throttle
//  decision. The trigger plumbing itself (UIKit assertions, scene phases) is
//  exercised on-device.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

final class ForegroundSyncTriggerTests: XCTestCase {

    private let interval = BackgroundSyncCoordinator.autoSyncMinimumInterval
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testActivationThrottle_firstEverTrigger_runs() {
        XCTAssertTrue(BackgroundSyncCoordinator.shouldRunActivationSync(
            lastRun: nil, now: t0, minimumInterval: interval))
    }

    func testActivationThrottle_withinInterval_isSuppressed() {
        XCTAssertFalse(BackgroundSyncCoordinator.shouldRunActivationSync(
            lastRun: t0, now: t0.addingTimeInterval(interval - 1), minimumInterval: interval))
    }

    func testActivationThrottle_atExactInterval_runs() {
        XCTAssertTrue(BackgroundSyncCoordinator.shouldRunActivationSync(
            lastRun: t0, now: t0.addingTimeInterval(interval), minimumInterval: interval))
    }

    func testActivationThrottle_pastInterval_runs() {
        XCTAssertTrue(BackgroundSyncCoordinator.shouldRunActivationSync(
            lastRun: t0, now: t0.addingTimeInterval(interval * 3), minimumInterval: interval))
    }
}
#endif
