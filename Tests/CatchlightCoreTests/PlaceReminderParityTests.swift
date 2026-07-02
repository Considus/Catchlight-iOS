//
//  PlaceReminderParityTests.swift
//  CatchlightCoreTests — 2026-07-01 place/time reminder parity (owner decision)
//
//  A location ("where") reminder now participates in the done/state system
//  exactly like a time ("when") reminder: it makes a Take settleable, one
//  "Mark as done" settles it alongside any task items and time reminder, and
//  the Sequence filters treat it as a reminder. `LocationTrigger.isDone` is
//  additive — older payloads decode as not-done.
//

import XCTest
@testable import CatchlightCore

final class PlaceReminderParityTests: XCTestCase {

    private func place(isDone: Bool = false, alarmEnabled: Bool = true) -> LocationTrigger {
        LocationTrigger(latitude: 51.5, longitude: -0.1, radiusMetres: 150,
                        triggerOnArrival: true, locationName: "Office",
                        alarmEnabled: alarmEnabled, isDone: isDone)
    }

    // MARK: - Done model

    func testPlaceOnlyTake_isSettleable_andMarksDone() {
        var take = Take(blocks: [.textLine("pick up parcel")], locationReminder: place())
        XCTAssertTrue(take.canBeMarkedDone, "a place reminder makes a Take settleable")
        XCTAssertFalse(take.isMarkedDone)

        take.setMarkedDone(true)
        XCTAssertEqual(take.locationReminder?.isDone, true)
        XCTAssertTrue(take.isMarkedDone)

        take.setMarkedDone(false)
        XCTAssertEqual(take.locationReminder?.isDone, false)
        XCTAssertFalse(take.isMarkedDone)
    }

    func testMixedTake_doneRequiresEveryMarkerSettled() {
        var take = Take(blocks: [.textLine("errand"), .checkItem("buy stamps")],
                        locationReminder: place())
        take.setAllItemsComplete(true)
        XCTAssertFalse(take.isMarkedDone, "ticked items alone must not settle an un-done place")

        take.locationReminder?.isDone = true
        XCTAssertTrue(take.isMarkedDone)
    }

    func testPlainNote_isNeverSettleable() {
        let note = Take(blocks: [.textLine("just a thought")])
        XCTAssertFalse(note.canBeMarkedDone)
        XCTAssertFalse(note.isMarkedDone)
    }

    // MARK: - Codable (additive field)

    func testLocationTrigger_isDone_roundTripsAndDefaultsFalse() throws {
        let done = place(isDone: true)
        let decoded = try PlatformJSON.decode(LocationTrigger.self,
                                              from: try PlatformJSON.encode(done))
        XCTAssertEqual(decoded, done)

        // A pre-2026-07 payload (no isDone key) decodes as NOT done.
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try PlatformJSON.encode(place())) as? [String: Any])
        json.removeValue(forKey: "isDone")
        let legacy = try PlatformJSON.decode(LocationTrigger.self,
                                             from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(legacy.isDone)
    }

    // MARK: - Sequence filters

    func testFilter_requireReminder_matchesPlaceTake() {
        let placeTake = Take(blocks: [.textLine("errand")], locationReminder: place())
        var filter = SequenceFilter()
        filter.requireReminder = true
        XCTAssertTrue(filter.matches(placeTake),
                      "the Reminders toggle must match a place reminder like a time one")
    }

    func testFilter_noteOnly_excludesPlaceTake() {
        let placeTake = Take(blocks: [.textLine("errand")], locationReminder: place())
        var filter = SequenceFilter()
        filter.requireNoteOnly = true
        XCTAssertFalse(filter.matches(placeTake),
                       "a place-reminder Take is not 'note only'")
    }

    func testFilter_expired_staysTimeOnly() {
        // A place has no due instant — it can never be Expired.
        let placeTake = Take(blocks: [.textLine("errand")], locationReminder: place())
        var filter = SequenceFilter()
        filter.requireExpiredReminder = true
        XCTAssertFalse(filter.matches(placeTake))
    }
}
