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
        var exposure: SpotlightExposure = .none
        var indexed: [Take] = []
        var deindexed: [UUID] = []
        var deindexAllCount = 0
        func index(_ take: Take) { indexed.append(take) }
        func deindex(takeID: UUID) { deindexed.append(takeID) }
        func deindexAll() { deindexAllCount += 1 }
    }

    // MARK: - Title (activity-type label)

    func testTitle_noteOnlyTake_isNote() {
        let t = Take(blocks: [.textLine("x")], isNote: true)
        XCTAssertEqual(SpotlightAttributes.title(for: t), "Note")
    }

    func testTitle_taskTake_isTask() {
        let t = Take(blocks: [.checkItem("x")], isNote: true)
        XCTAssertEqual(SpotlightAttributes.title(for: t), "Task")
    }

    func testTitle_reminderBeatsTask() {
        var t = Take(blocks: [.checkItem("x")], isNote: true)
        t.timeReminder = TimeReminder(scheduledDate: Date(),
                                      notificationIdentifier: t.id.uuidString)
        XCTAssertEqual(SpotlightAttributes.title(for: t), "Reminder")
    }

    // MARK: - userInfo carries ONLY the Take UUID

    func testUserInfo_containsTakeID() {
        let t = Take(blocks: [.textLine("x")], isNote: true)
        let info = SpotlightAttributes.userInfo(for: t)
        XCTAssertEqual(info[SpotlightConstants.userInfoTakeIDKey] as? String,
                       t.id.uuidString)
    }

    func testUserInfo_doesNotLeakBodyText() {
        let secret = "Confidential body text that must never reach Spotlight"
        let t = Take(blocks: [.textLine(secret)], isNote: true)
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
        let t = Take(blocks: [.textLine(secret)], isNote: true)
        let item = SpotlightAttributes.makeItem(for: t, exposure: .type)!
        XCTAssertEqual(item.attributeSet.title, "Note")
        XCTAssertEqual(item.attributeSet.displayName, "Note")
        XCTAssertNotEqual(item.attributeSet.title, secret)
        XCTAssertNotEqual(item.attributeSet.displayName, secret)
    }

    func testMakeItem_contentDescriptionIsNil() {
        // Load-bearing: this is the field where the body would otherwise live.
        // Leaving it nil is the privacy invariant.
        let t = Take(blocks: [.textLine("x")], isNote: true)
        let item = SpotlightAttributes.makeItem(for: t, exposure: .type)!
        XCTAssertNil(item.attributeSet.contentDescription)
    }

    func testMakeItem_uniqueIdentifierIsTakeUUID() {
        let t = Take(blocks: [.textLine("x")], isNote: true)
        let item = SpotlightAttributes.makeItem(for: t, exposure: .type)!
        XCTAssertEqual(item.uniqueIdentifier, t.id.uuidString)
    }

    func testMakeItem_domainIdentifierIsBundlePrefix() {
        let t = Take(blocks: [.textLine("x")], isNote: true)
        let item = SpotlightAttributes.makeItem(for: t, exposure: .type)!
        XCTAssertEqual(item.domainIdentifier, SpotlightConstants.domainIdentifier)
    }

    func testMakeItem_doesNotEmbedBodyInAnyKnownTextField() {
        let secret = "TOP-SECRET-BODY-PAYLOAD-XYZ123"
        let t = Take(blocks: [.textLine(secret)], isNote: true)
        let item = SpotlightAttributes.makeItem(for: t, exposure: .type)!
        let attrs = item.attributeSet
        // Scan the broad text surface area on a Spotlight item — every field
        // that could theoretically be indexed and surfaced in search results.
        XCTAssertNotEqual(attrs.title, secret)
        XCTAssertNotEqual(attrs.displayName, secret)
        XCTAssertNil(attrs.contentDescription)
        XCTAssertNil(attrs.keywords)
        XCTAssertNil(attrs.textContent)
    }

    // MARK: - Exposure levels (D-110)

    func testMakeItem_noneExposure_returnsNil() {
        let t = Take(blocks: [.textLine("secret body")], isNote: true)
        XCTAssertNil(SpotlightAttributes.makeItem(for: t, exposure: .none))
    }

    func testContentDescription_typeExposure_isNil() {
        let t = Take(blocks: [.textLine("secret body")], isNote: true)
        XCTAssertNil(SpotlightAttributes.contentDescription(for: t, exposure: .type))
    }

    func testContentDescription_firstLine_isFirstNonEmptyLine() {
        let t = Take(blocks: [.textLine(""), .textLine("first real line"), .textLine("second")], isNote: true)
        XCTAssertEqual(SpotlightAttributes.contentDescription(for: t, exposure: .firstLine), "first real line")
    }

    func testContentDescription_all_isFullPlainText() {
        let t = Take(blocks: [.textLine("line one"), .textLine("line two")], isNote: true)
        XCTAssertEqual(SpotlightAttributes.contentDescription(for: t, exposure: .all), "line one\nline two")
    }

    func testMakeItem_firstLine_titleStaysTypeLabel_bodyInDescriptionAndTextContent() {
        let t = Take(blocks: [.textLine("call the framer")], isNote: true)
        let item = SpotlightAttributes.makeItem(for: t, exposure: .firstLine)!
        XCTAssertEqual(item.attributeSet.title, "Note")            // type label, never the body
        XCTAssertEqual(item.attributeSet.displayName, "Note")
        XCTAssertEqual(item.attributeSet.contentDescription, "call the framer")   // subtitle shown in results
        XCTAssertEqual(item.attributeSet.textContent, "call the framer")          // the full-text search field
    }

    func testMakeItem_all_bodyLandsInTextContentForFullTextSearch() {
        // Regression for the 2026-07-24 report: at full-text the type label matched
        // but interior body words did not, because the body was only in
        // `contentDescription`. It must ALSO be in `textContent` — the field
        // Spotlight word-searches — and the two must agree.
        let t = Take(blocks: [.textLine("meeting with Considus about the roadmap")], isNote: true)
        let item = SpotlightAttributes.makeItem(for: t, exposure: .all)!
        XCTAssertEqual(item.attributeSet.textContent, "meeting with Considus about the roadmap")
        XCTAssertEqual(item.attributeSet.textContent, item.attributeSet.contentDescription,
                       "both body fields share one exposure-gated source and must not diverge")
    }

    // MARK: - keywords (the field GLOBAL Spotlight surfaces — proven on-device 2026-07-24)

    func testKeywords_typeExposure_isNil() {
        let t = Take(blocks: [.textLine("secret body")], isNote: true)
        XCTAssertNil(SpotlightAttributes.keywords(for: t, exposure: .type))
    }

    func testKeywords_all_tokenisesBodyWords_dedupedAndLowercased() {
        let t = Take(blocks: [.textLine("Considus Considus roadmap A")], isNote: true)
        let kw = SpotlightAttributes.keywords(for: t, exposure: .all)
        // "considus" deduped, "roadmap" kept, single-char "A" dropped (<2 chars).
        XCTAssertEqual(kw, ["considus", "roadmap"])
    }

    func testKeywords_firstLine_onlyFirstLineTokens() {
        let t = Take(blocks: [.textLine("alpha bravo"), .textLine("charlie")], isNote: true)
        XCTAssertEqual(SpotlightAttributes.keywords(for: t, exposure: .firstLine), ["alpha", "bravo"])
    }

    func testMakeItem_all_bodyWordAppearsInKeywords() {
        // The actual on-device fix: an interior body word must be a keyword, since
        // that is the body field global home-screen Spotlight surfaces.
        let t = Take(blocks: [.textLine("meeting with zorbleflux tomorrow")], isNote: true)
        let item = SpotlightAttributes.makeItem(for: t, exposure: .all)!
        XCTAssertEqual(item.attributeSet.keywords?.contains("zorbleflux"), true)
    }
    #endif

    // MARK: - Recording-mock contract (the wiring tests)

    func testIndexer_indexCalledOnce_recordsTheTake() {
        let mock = RecordingIndexer()
        let t = Take(blocks: [.textLine("x")], isNote: true)
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
