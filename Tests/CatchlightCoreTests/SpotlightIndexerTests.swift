//
//  SpotlightIndexerTests.swift
//  CatchlightCoreTests — Task 6.19
//
//  The privacy contract on Spotlight indexing is load-bearing: the encrypted
//  body must never reach the OS index, the userInfo payload must contain only
//  the Take UUID, and lapse must trigger a clean deindex-all. These tests
//  exercise both the pure attribute builder (no CSSearchableIndex needed) and
//  the protocol-driven indexing/deindexing flow via a recording mock.
//

import XCTest
@testable import CatchlightCore

#if canImport(CoreSpotlight)
import CoreSpotlight
#endif

final class SpotlightIndexerTests: XCTestCase {

    // MARK: - Recording mock

    final class RecordingIndexer: SpotlightIndexing, @unchecked Sendable {
        var indexed: [Take] = []
        var deindexed: [UUID] = []
        var deindexAllCount = 0
        func index(_ take: Take) { indexed.append(take) }
        func deindex(takeID: UUID) { deindexed.append(takeID) }
        func deindexAll() { deindexAllCount += 1 }
    }

    // MARK: - Title (activity-type label)

    func testTitle_noteOnlyTake_isNote() {
        let t = Take(bodyText: "x", isNote: true)
        XCTAssertEqual(SpotlightAttributes.title(for: t), "Note")
    }

    func testTitle_taskTake_isTask() {
        let t = Take(bodyText: "x", isNote: true, isTask: true)
        XCTAssertEqual(SpotlightAttributes.title(for: t), "Task")
    }

    func testTitle_reminderBeatsTask() {
        var t = Take(bodyText: "x", isNote: true, isTask: true)
        t.timeReminder = TimeReminder(scheduledDate: Date(),
                                      notificationIdentifier: t.id.uuidString)
        XCTAssertEqual(SpotlightAttributes.title(for: t), "Reminder")
    }

    // MARK: - userInfo carries ONLY the Take UUID

    func testUserInfo_containsTakeID() {
        let t = Take(bodyText: "x", isNote: true)
        let info = SpotlightAttributes.userInfo(for: t)
        XCTAssertEqual(info[SpotlightConstants.userInfoTakeIDKey] as? String,
                       t.id.uuidString)
    }

    func testUserInfo_doesNotLeakBodyText() {
        let secret = "Confidential body text that must never reach Spotlight"
        let t = Take(bodyText: secret, isNote: true)
        let info = SpotlightAttributes.userInfo(for: t)
        for (_, value) in info {
            if let str = value as? String {
                XCTAssertFalse(str.contains(secret),
                               "Body text leaked into userInfo: \(info)")
            }
        }
        XCTAssertEqual(info.count, 1, "userInfo should hold only the take ID.")
    }

    // MARK: - CSSearchableItem privacy contract

    #if canImport(CoreSpotlight)
    func testMakeItem_titleIsActivityTypeNotBody() {
        let secret = "do not index this body"
        let t = Take(bodyText: secret, isNote: true)
        let item = SpotlightAttributes.makeItem(for: t)
        XCTAssertEqual(item.attributeSet.title, "Note")
        XCTAssertEqual(item.attributeSet.displayName, "Note")
        XCTAssertNotEqual(item.attributeSet.title, secret)
        XCTAssertNotEqual(item.attributeSet.displayName, secret)
    }

    func testMakeItem_contentDescriptionIsNil() {
        // Load-bearing: this is the field where the body would otherwise live.
        // Leaving it nil is the privacy invariant.
        let t = Take(bodyText: "x", isNote: true)
        let item = SpotlightAttributes.makeItem(for: t)
        XCTAssertNil(item.attributeSet.contentDescription)
    }

    func testMakeItem_uniqueIdentifierIsTakeUUID() {
        let t = Take(bodyText: "x", isNote: true)
        let item = SpotlightAttributes.makeItem(for: t)
        XCTAssertEqual(item.uniqueIdentifier, t.id.uuidString)
    }

    func testMakeItem_domainIdentifierIsBundlePrefix() {
        let t = Take(bodyText: "x", isNote: true)
        let item = SpotlightAttributes.makeItem(for: t)
        XCTAssertEqual(item.domainIdentifier, SpotlightConstants.domainIdentifier)
    }

    func testMakeItem_doesNotEmbedBodyInAnyKnownTextField() {
        let secret = "TOP-SECRET-BODY-PAYLOAD-XYZ123"
        let t = Take(bodyText: secret, isNote: true)
        let item = SpotlightAttributes.makeItem(for: t)
        let attrs = item.attributeSet
        // Scan the broad text surface area on a Spotlight item — every field
        // that could theoretically be indexed and surfaced in search results.
        XCTAssertNotEqual(attrs.title, secret)
        XCTAssertNotEqual(attrs.displayName, secret)
        XCTAssertNil(attrs.contentDescription)
        XCTAssertNil(attrs.keywords)
        XCTAssertNil(attrs.textContent)
    }
    #endif

    // MARK: - Recording-mock contract (the wiring tests)

    func testIndexer_indexCalledOnce_recordsTheTake() {
        let mock = RecordingIndexer()
        let t = Take(bodyText: "x", isNote: true)
        mock.index(t)
        XCTAssertEqual(mock.indexed.count, 1)
        XCTAssertEqual(mock.indexed.first?.id, t.id)
    }

    func testIndexer_deindexByID_isRecorded() {
        let mock = RecordingIndexer()
        let id = UUID()
        mock.deindex(takeID: id)
        XCTAssertEqual(mock.deindexed, [id])
    }

    func testIndexer_deindexAll_isCounted() {
        let mock = RecordingIndexer()
        mock.deindexAll()
        mock.deindexAll()
        XCTAssertEqual(mock.deindexAllCount, 2)
    }
}
