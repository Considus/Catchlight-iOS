//
//  TakeBlankTests.swift
//  CatchlightCoreTests — `Take.isBlank`, the rule every editor uses to decide whether a
//  closing draft is discarded or saved (owner 2026-08-16).
//
//  A false "blank" deletes a user's Take, so each thing that keeps a Take alive with no
//  prose is pinned on its own.
//

import XCTest
@testable import CatchlightCore

final class TakeBlankTests: XCTestCase {

    func testNoBlocksIsBlank() {
        XCTAssertTrue(Take(blocks: []).isBlank)
    }

    func testWhitespaceOnlyProseIsBlank() {
        XCTAssertTrue(Take(blocks: [.textLine("  \n\t "), .textLine("")]).isBlank)
    }

    func testProseIsNotBlank() {
        XCTAssertFalse(Take(blocks: [.textLine("milk")]).isBlank)
    }

    func testAnEmptyTaskItemKeepsItAlive() {
        XCTAssertFalse(Take(blocks: [.checkItem("")]).isBlank)
    }

    func testAReminderKeepsItAlive() {
        var take = Take(blocks: [])
        take.timeReminder = TimeReminder(scheduledDate: Date(timeIntervalSince1970: 1_780_000_000),
                                         notificationIdentifier: "r")
        XCTAssertFalse(take.isBlank)
    }

    func testAPlaceKeepsItAlive() {
        var take = Take(blocks: [])
        take.locationReminder = LocationTrigger(latitude: 51.5, longitude: -0.12, radiusMetres: 150,
                                                triggerOnArrival: true)
        XCTAssertFalse(take.isBlank)
    }

    func testAnAttachmentKeepsItAlive() {
        var take = Take(blocks: [])
        take.attachments = [Attachment(mimeType: "image/jpeg", encryptedData: Data([1]), hmac: Data([2]))]
        XCTAssertFalse(take.isBlank)
    }

    /// The Obie takes no exception: an emptied Obie is blank like any other Take.
    func testAnEmptiedObieIsBlank() {
        var take = Take(blocks: [.textLine("")])
        take.isObie = true
        XCTAssertTrue(take.isBlank)
    }
}
