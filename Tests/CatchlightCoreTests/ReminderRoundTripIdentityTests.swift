//
//  ReminderRoundTripIdentityTests.swift
//  CatchlightCoreTests
//
//  Regression guard for the single-device "phantom conflict" (owner-reported
//  2026-06-27). A reminder Take whose `scheduledDate` carries sub-millisecond
//  precision did not survive the serialisation round trip unchanged — the wire
//  format (`ISO8601`, `…SSS'Z'`) is millisecond-resolution, so the decoded Take
//  compared `!=` to its in-memory original. With `modifiedAt` unchanged, the sync
//  engine's `ConflictResolver` then hit its `(localChanged:false, remoteChanged:false)`
//  branch and SURFACED A CONFLICT — even with only one device in play.
//
//  `Take.createdAt` / `modifiedAt` are already normalised to milliseconds for exactly
//  this reason; these tests assert the SAME guarantee for `TimeReminder.scheduledDate`.
//

import XCTest
@testable import CatchlightCore

final class ReminderRoundTripIdentityTests: XCTestCase {

    private func roundTrip(_ take: Take) throws -> Take {
        try PlatformJSON.decode(Take.self, from: PlatformJSON.encode(take))
    }

    /// A reminder whose `scheduledDate` has sub-millisecond precision (as `Date()`
    /// does) must round-trip byte-identical — otherwise every sync re-reads it as a
    /// changed Take. THIS is the reproduction: it fails before the fix.
    func testReminderWithSubMillisecondDateRoundTripsEqual() throws {
        // A timestamp with sub-millisecond precision, like `Date()` produces.
        let subMs = Date(timeIntervalSince1970: 1_780_000_000.123_456_7)
        let id = UUID()
        var take = Take(blocks: [.textLine("Crypto rewards")], isNote: false)
        take.timeReminder = TimeReminder(scheduledDate: subMs,
                                         notificationIdentifier: id.uuidString)

        let restored = try roundTrip(take)
        XCTAssertEqual(restored, take,
            "A reminder Take must survive serialisation unchanged; a drifting scheduledDate makes sync flag a phantom conflict.")
        XCTAssertEqual(restored.timeReminder?.scheduledDate, take.timeReminder?.scheduledDate,
            "scheduledDate drifted across the round trip — it is not millisecond-normalised like createdAt/modifiedAt.")
    }

    /// The exact single-device symptom: in-memory Take vs the SAME Take returned from
    /// the cloud, with the last-sync watermark AFTER both — neither side "changed".
    /// Must resolve to `.noChange`, never `.conflict`.
    func testSingleDeviceNoOpSyncIsNotAConflict() throws {
        let subMs = Date(timeIntervalSince1970: 1_780_000_000.987_654_3)
        let id = UUID()
        var local = Take(blocks: [.textLine("Test weekly reminders")], isNote: false)
        local.timeReminder = TimeReminder(scheduledDate: subMs,
                                          notificationIdentifier: id.uuidString,
                                          recurrence: .weekly)

        let remote = try roundTrip(local)                 // came back from the cloud
        let afterBoth = local.modifiedAt.addingTimeInterval(60)   // last sync is later

        XCTAssertEqual(ConflictResolver.decide(local: local, remote: remote, lastSync: afterBoth),
                       .noChange,
                       "One device, no edits — sync must see no change, not a conflict.")
    }

    /// Control: a whole-minute reminder (what the date picker produces) already
    /// round-trips fine, so the fix must not disturb it.
    func testWholeMinuteReminderRoundTripsEqual() throws {
        let whole = ISO8601.date(from: "2026-07-01T20:00:00.000Z")!
        let id = UUID()
        var take = Take(blocks: [.textLine("Monthly reminder test")], isNote: false)
        take.timeReminder = TimeReminder(scheduledDate: whole,
                                         notificationIdentifier: id.uuidString,
                                         recurrence: .monthly)

        XCTAssertEqual(try roundTrip(take), take)
    }
}
