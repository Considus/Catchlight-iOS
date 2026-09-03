//
//  TakeRoundTripIdentityTests.swift
//  CatchlightCoreTests — 2026-09-03
//
//  Widens the PR #79 guarantee from Dates to EVERY field.
//
//  `ReminderRoundTripIdentityTests` pins the original phantom-conflict fix: a
//  sub-millisecond `Date` did not survive the wire format, so a decoded Take
//  compared `!=` to its in-memory original and `ConflictResolver` raised a
//  conflict on a single device with no edits.
//
//  The rule written down at the time was "millisecond-normalise every new DATE
//  field". That rule is too narrow. `Take` is synthesised-`Equatable`, so EVERY
//  stored property participates in the comparison the sync engine makes — and a
//  field added later that does not survive the round trip re-introduces the same
//  phantom-conflict class without touching a single Date. `manualOrder` (payload
//  v3, 2026-08-14) arrived after the resolver was written and obeys the Date rule
//  perfectly, which is exactly why a Date-shaped rule would not catch it.
//
//  These tests therefore assert the round trip over a MAXIMALLY populated Take,
//  so any future field is covered by construction rather than by remembering.
//

import XCTest
@testable import CatchlightCore

final class TakeRoundTripIdentityTests: XCTestCase {

    private func roundTrip(_ take: Take) throws -> Take {
        try PlatformJSON.decode(Take.self, from: PlatformJSON.encode(take))
    }

    /// Every field set to a non-default value, with sub-millisecond dates and a
    /// non-terminating fraction for `manualOrder`. If ANY property fails to survive
    /// the round trip, the whole-struct comparison fails and the sync engine will
    /// raise a phantom conflict on a single device.
    private func maximalTake() -> Take {
        let id = UUID()
        return Take(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_780_000_000.123_456_7),
            modifiedAt: Date(timeIntervalSince1970: 1_780_000_500.987_654_3),
            blocks: [
                .textLine("Buy film for the weekend shoot"),
                .checkItem("Kodak Portra 400", isComplete: false),
                .checkItem("Lens cloth", isComplete: true)
            ],
            contentType: "blocks/v2",
            isNote: true,
            isObie: false,
            timeReminder: TimeReminder(
                scheduledDate: Date(timeIntervalSince1970: 1_780_001_000.555_555_5),
                isDelivered: true,
                notificationIdentifier: id.uuidString,
                alarmEnabled: false,
                isDone: true,
                isAllDay: true,
                recurrence: .weekly,
                weekdays: [2, 4, 6]
            ),
            locationReminder: LocationTrigger(
                latitude: 51.507_351_9,
                longitude: -0.127_758_3,
                radiusMetres: 150.5,
                triggerOnArrival: true,
                locationName: "Studio",
                alarmEnabled: false,
                isDone: true
            ),
            attachments: [],
            isSeeded: true,
            isImportant: true,
            manualOrder: 1.0 / 3.0
        )
    }

    /// THE GUARANTEE: a fully-populated Take survives serialisation unchanged.
    func testMaximallyPopulatedTakeRoundTripsEqual() throws {
        let take = maximalTake()
        XCTAssertEqual(try roundTrip(take), take,
            "A fully-populated Take did not survive the round trip. Whichever field drifted will make every sync raise a phantom conflict on a single device — see PR #79 and D-250.")
    }

    /// `manualOrder` is a `Double`, and `ManualOrder` produces midpoints, so the
    /// values in the wild are fractions rather than whole numbers. Pinned separately
    /// because it is the field that arrived after the resolver and after the Date rule.
    func testManualOrderFractionRoundTripsExactly() throws {
        for value in [1.0 / 3.0, 0.1 + 0.2, .leastNormalMagnitude, 1e-300, 12_345.678_901_234_5] as [Double] {
            var take = Take(blocks: [.textLine("ordered")])
            take.manualOrder = value
            XCTAssertEqual(try roundTrip(take).manualOrder, value,
                "manualOrder \(value) drifted across the round trip — a reordered Take would then phantom-conflict on every sync.")
        }
    }

    /// The single-device symptom itself, over the maximal Take: the in-memory copy
    /// versus the same Take returned from the cloud, with the watermark AFTER both.
    /// Neither side changed, so this MUST resolve to `.noChange` and never a conflict.
    func testMaximalTake_singleDeviceSync_resolvesToNoChange() throws {
        let local = maximalTake()
        let remote = try roundTrip(local)
        let afterBoth = local.modifiedAt.addingTimeInterval(3600)
        XCTAssertEqual(ConflictResolver.decide(local: local, remote: remote, lastSync: afterBoth),
                       .noChange,
            "A Take that has not changed on either side resolved to something other than .noChange — this is the phantom conflict the user sees as 'N Takes changed on another device'.")
    }
}
