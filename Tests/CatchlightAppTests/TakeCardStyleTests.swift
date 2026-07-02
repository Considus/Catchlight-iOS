//
//  TakeCardStyleTests.swift
//  CatchlightAppTests — 2026-07-02 review-audit follow-up
//
//  First direct coverage for the D-044 card colour precedence
//  (overdue ruby → Obie gold → done grey → Task/Remind quadrant → none),
//  including the 2026-07-01 place/time parity branch: a location reminder
//  takes the Remind border like a time one, and — having no due instant —
//  can never be OVERDUE.
//
//  iOS-only — gated on `canImport(Catchlight)`.
//

#if canImport(Catchlight)
import XCTest
import SwiftUI
@testable import Catchlight
@testable import CatchlightCore

final class TakeCardStyleTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func place(isDone: Bool = false) -> LocationTrigger {
        LocationTrigger(latitude: 51.5, longitude: -0.1, radiusMetres: 150,
                        triggerOnArrival: true, locationName: "Office", isDone: isDone)
    }

    private func style(_ take: Take) -> TakeCardStyle {
        TakeCardStyle(take: take, scheme: .dark, now: now)
    }

    func testPlainNote_hasNoVisibleBorder() {
        let s = style(Take(blocks: [.textLine("just a note")]))
        XCTAssertEqual(s.border, s.surface, "a plain Note draws no border")
        XCTAssertFalse(s.isOverdue)
        XCTAssertFalse(s.isDone)
    }

    func testTimeReminder_takesReminderBorder() {
        var take = Take(blocks: [.textLine("call back")])
        take.timeReminder = TimeReminder(scheduledDate: now.addingTimeInterval(3600),
                                         notificationIdentifier: take.id.uuidString)
        XCTAssertEqual(style(take).border, Quadrant.reminder(.dark))
    }

    /// The place/time parity branch (owner 2026-07-01): a "where" lights the
    /// SAME Remind border as a "when".
    func testPlaceReminder_takesReminderBorder() {
        let take = Take(blocks: [.textLine("pick up parcel")], locationReminder: place())
        let s = style(take)
        XCTAssertEqual(s.border, Quadrant.reminder(.dark))
        XCTAssertFalse(s.isOverdue, "a place has no due instant — it can never be overdue")
    }

    func testOverdue_beatsEverything() {
        var take = Take(blocks: [.textLine("late")], isObie: true)
        take.timeReminder = TimeReminder(scheduledDate: now.addingTimeInterval(-3600),
                                         notificationIdentifier: take.id.uuidString)
        let s = style(take)
        XCTAssertTrue(s.isOverdue)
        XCTAssertEqual(s.border, Color.ckCardOverdueBorder,
                       "overdue ruby outranks even the Obie gold (D-044)")
    }

    func testDonePlace_takesDoneGrey() {
        let take = Take(blocks: [.textLine("errand")], locationReminder: place(isDone: true))
        let s = style(take)
        XCTAssertTrue(s.isDone)
        XCTAssertEqual(s.border, Color.ckCardDoneBorder)
        XCTAssertEqual(s.bodyText, Color.ckTextComplete, "done recedes the body text")
    }

    func testObie_beatsDone() {
        var take = Take(blocks: [.checkItem("x", isComplete: true)], isObie: true)
        take.setAllItemsComplete(true)
        XCTAssertEqual(style(take).border, Color.ckCardObieBorder,
                       "Obie gold outranks the done grey (D-044)")
    }

    func testTask_beatsReminder_inQuadrantTier() {
        var take = Take(blocks: [.checkItem("x", isComplete: false)])
        take.locationReminder = place()
        XCTAssertEqual(style(take).border, Quadrant.task(.dark),
                       "a Task-and-reminder Take borders as Task (D-044 order)")
    }
}
#endif
