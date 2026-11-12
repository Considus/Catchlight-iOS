//
//  TakeCardStyleTests.swift
//  CatchlightAppTests — 2026-07-02 review-audit follow-up
//
//  The card edge precedence (owner 2026-11-12, "Option 1"): overdue ruby → Obie lit →
//  Important mid edge → the quiet line for everything else (notes, Tasks, reminders,
//  done). A location reminder, having no due instant, can never be OVERDUE.
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
        XCTAssertEqual(s.border, Color.ckLine, "a plain Note draws the quiet line edge")
        XCTAssertFalse(s.isOverdue)
        XCTAssertFalse(s.isDone)
    }

    func testTimeReminder_takesTheLine() {
        var take = Take(blocks: [.textLine("call back")])
        take.timeReminder = TimeReminder(scheduledDate: now.addingTimeInterval(3600),
                                         notificationIdentifier: take.id.uuidString)
        XCTAssertEqual(style(take).border, Color.ckLine)
    }

    func testPlaceReminder_takesTheLine() {
        let take = Take(blocks: [.textLine("pick up parcel")], locationReminder: place())
        let s = style(take)
        XCTAssertEqual(s.border, Color.ckLine)
        XCTAssertFalse(s.isOverdue, "a place has no due instant — it can never be overdue")
    }

    func testOverdue_beatsEverything() {
        var take = Take(blocks: [.textLine("late")], isObie: true)
        take.timeReminder = TimeReminder(scheduledDate: now.addingTimeInterval(-3600),
                                         notificationIdentifier: take.id.uuidString)
        let s = style(take)
        XCTAssertTrue(s.isOverdue)
        XCTAssertEqual(s.border, Color.ckCardOverdueBorder,
                       "overdue ruby outranks even the Obie gold")
    }

    func testDonePlace_takesTheLine() {
        let take = Take(blocks: [.textLine("errand")], locationReminder: place(isDone: true))
        let s = style(take)
        XCTAssertTrue(s.isDone)
        XCTAssertEqual(s.border, Color.ckLine)
        XCTAssertEqual(s.bodyText, Color.ckTextComplete, "done recedes the body text")
    }

    func testObie_beatsDone() {
        var take = Take(blocks: [.checkItem("x", isComplete: true)], isObie: true)
        take.setAllItemsComplete(true)
        XCTAssertEqual(style(take).border, Color.ckCardObieBorder,
                       "the Obie keeps its edge when done")
    }

    func testTask_takesTheLine() {
        var take = Take(blocks: [.checkItem("x", isComplete: false)])
        take.locationReminder = place()
        XCTAssertEqual(style(take).border, Color.ckLine)
    }

    func testImportant_takesTheMidEdge_andTheObieOutranksIt() {
        XCTAssertEqual(style(Take(blocks: [.textLine("a")], isImportant: true)).border, Color.ckCardImportantBorder)
        XCTAssertEqual(style(Take(blocks: [.textLine("b")], isObie: true)).border, Color.ckCardObieBorder)
    }

    func testFormerObie_takesTheImportantEdge() {
        var take = Take(blocks: [.textLine("a")], isObie: true)
        take.isObie = false
        XCTAssertEqual(style(take).border, Color.ckCardImportantBorder)
    }

    func testImportantOverdue_isRuby() {
        var take = Take(blocks: [.textLine("late")], isImportant: true)
        take.timeReminder = TimeReminder(scheduledDate: now.addingTimeInterval(-3600),
                                         notificationIdentifier: take.id.uuidString)
        XCTAssertEqual(style(take).border, Color.ckCardOverdueBorder)
    }

    /// `HeldCardIrisUITests` allows for this stroke width when it finds the card's edges.
    func testBorderWidth_isWhatTheHeldCardUITestAssumes() {
        XCTAssertEqual(TakeCardStyle.borderWidth, 0.75)
    }
}
#endif
