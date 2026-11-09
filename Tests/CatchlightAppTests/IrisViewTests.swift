//
//  IrisViewTests.swift
//  CatchlightTests (app module)
//
//  Covers which of the Iris's six lights are lit for a Take, and which inner
//  shape it draws: one type shows that type's shape, two or more show four
//  dots, none shows the Note shape. Important is a light, never a type.
//

import XCTest
import CatchlightCore
@testable import Catchlight

final class IrisViewTests: XCTestCase {

    private func litLights(_ take: Take) -> Set<IrisLight> {
        Set(IrisView.lights(for: take).filter { $0.value }.map(\.key))
    }

    func testLights_coverAllSixInClockwiseOrder() {
        XCTAssertEqual(IrisLight.allCases, [.important, .task, .audio, .note, .image, .reminder])
        XCTAssertEqual(IrisView.lights(for: Take(blocks: [.textLine("a")])).count, 6)
    }

    func testPlainNote_noteShape_onlyNoteLit() {
        let take = Take(blocks: [.textLine("a thought")])
        XCTAssertEqual(IrisView.innerShape(for: take), .note)
        XCTAssertEqual(litLights(take), [.note])
    }

    func testTaskOnly_taskShape() {
        let take = Take(blocks: [.checkItem("milk")], isNote: false)
        XCTAssertEqual(IrisView.innerShape(for: take), .task)
        XCTAssertEqual(litLights(take), [.task])
    }

    func testNoteWithReminder_fourDots() {
        var take = Take(blocks: [.textLine("call the framer")])
        take.timeReminder = TimeReminder(scheduledDate: .now, notificationIdentifier: "x")
        XCTAssertEqual(IrisView.innerShape(for: take), .fourDots)
        XCTAssertEqual(litLights(take), [.note, .reminder])
    }

    func testImportantNote_noteShape_importantAndNoteLit() {
        let take = Take(blocks: [.textLine("big")], isImportant: true)
        XCTAssertEqual(IrisView.innerShape(for: take), .note)
        XCTAssertEqual(litLights(take), [.important, .note])
    }

    func testObieWithNothingElse_keepsItsTypeShape() {
        let note = Take(blocks: [.textLine("the star")], isObie: true)
        XCTAssertEqual(IrisView.innerShape(for: note), .note)
        XCTAssertEqual(litLights(note), [.important, .note])

        let task = Take(blocks: [.checkItem("ship it")], isNote: false, isObie: true)
        XCTAssertEqual(IrisView.innerShape(for: task), .task)
    }

    func testNoTypes_noteShape_nothingLit() {
        let take = Take(blocks: [.textLine("bare")], isNote: false)
        XCTAssertEqual(IrisView.innerShape(for: take), .note)
        XCTAssertEqual(litLights(take), [])
    }
}
