//
//  NoticeCodeTests.swift
//  CatchlightAppTests
//
//  Pins the diagnostics reference codes: the line format support reads, the display
//  text Notice History shows, and the rule that every log line goes through `Notice`.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight
import CatchlightCore
import StoreKit

final class NoticeCodeTests: XCTestCase {

    /// The message part follows the device language, so it is compared with the notice's
    /// own message rather than a fixed English string; the reference never changes.
    func testLogLine_isReferenceThenMessage() {
        XCTAssertEqual(Notice.saveFailed.reference, "CCIOS-202")
        XCTAssertEqual(Notice.saveFailed.logLine, "[CCIOS-202] " + Notice.saveFailed.message)
        // Developer-only lines are English in every language.
        XCTAssertEqual(Notice.takeDeleted.logLine, "[CCIOS-914] Take deleted")
    }

    /// Codes are permanent: support reads old exports against them. Renumbering,
    /// reusing or deleting a code fails here; a new code is added to this table.
    func testCodesNeverChange() {
        let pinned: [String: Int] = [
            "syncPaused": 101,
            "syncProblem": 102,
            "syncLockHeld": 103,
            "libraryNotSaving": 104,
            "cloudFolderStale": 105,
            "cloudFolderUnresolvable": 106,
            "loadFailed": 201,
            "saveFailed": 202,
            "saveInPlaceFailed": 203,
            "reorderFailed": 204,
            "importFailed": 205,
            "deleteFailed": 206,
            "cleanupFailed": 207,
            "setObieFailed": 208,
            "replaceObieFailed": 209,
            "conflictChoiceFailed": 210,
            "conflictResolutionFailed": 211,
            "privacyPhraseMissing": 212,
            "readOnlyLapsed": 213,
            "exportFailed": 214,
            "remindersSilenced": 215,
            "conflictsChanged": 301,
            "conflictsUnverified": 302,
            "takeAwaitingConflict": 303,
            "conflictEditKeptAsCopy": 304,
            "savedNotAsObie": 305,
            "obieAwaitingConflict": 306,
            "conflictsUnreadable": 307,
            "takesQuarantined": 401,
            "capturesUnopenable": 402,
            "spotlightReindexSkipped": 901,
            "spotlightReindexed": 902,
            "cloudFolderConnected": 903,
            "cloudFolderDisconnected": 904,
            "cloudBookmarkReminted": 905,
            "lockedCaptureCommitRequested": 906,
            "lockedCaptureBlankDiscarded": 907,
            "lockedCaptureDiscarded": 908,
            "paywallDraftHeld": 909,
            "paywallDraftDropped": 910,
            "paywallDraftSaved": 911,
            "takeSaved": 912,
            "timelineReordered": 913,
            "takeDeleted": 914,
            "backgroundSyncNotScheduled": 915,
            "reminderNotScheduled": 916,
            "notificationPermission": 917,
            "reminderPastDated": 918,
            "takesHeldBack": 107,
            "watermarkPrepareFailed": 920,
            "watermarkStepFailed": 921,
            "libraryOpenFailed": 922,
            "conflictNotKept": 923,
            "conflictFileNotRemoved": 924,
            "statusBarStyleKept": 925,
            "cloudFolderCheckFailed": 926,
            "storeEnvironment": 927,
            "subscriptionTransaction": 928
        ]
        let current = Dictionary(uniqueKeysWithValues: NoticeCode.allCases.map { ("\($0)", $0.rawValue) })
        XCTAssertEqual(current, pinned)
    }

    /// Same wording, different place: the code is what tells them apart.
    func testSameWording_differentCodes() {
        XCTAssertEqual(Notice.saveFailed.message, Notice.saveInPlaceFailed.message)
        XCTAssertNotEqual(Notice.saveFailed.reference, Notice.saveInPlaceFailed.reference)
    }

    func testCategory_followsTheHundreds() {
        XCTAssertEqual(Notice.syncProblem.category, .sync)
        XCTAssertEqual(Notice.deleteFailed.category, .storage)
        XCTAssertEqual(Notice.conflictsChanged(2).category, .conflict)
        XCTAssertEqual(Notice.takesQuarantined(1).category, .quarantine)
        XCTAssertEqual(Notice.takeSaved.category, .lifecycle)
    }

    /// 950–999 belongs to Catchlight-Core.
    func testNoAppCode_inCoreRange() {
        XCTAssertTrue(NoticeCode.allCases.allSatisfy { !(950...999).contains($0.rawValue) })
    }

    /// A lasting banner is recorded once per onset: not again while it stays, and again
    /// after it clears and comes back.
    func testOnset_recordsOncePerOnset() throws {
        let suite = "NoticeOnsetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let log = DiagnosticsLog(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("onset-\(UUID().uuidString).json"))
        let lines = { log.entries().map(\.message) }

        NoticeOnset.update(.readOnlyLapsed, active: true, defaults: defaults, log: log)
        NoticeOnset.update(.readOnlyLapsed, active: true, defaults: defaults, log: log)
        XCTAssertEqual(lines().count, 1)
        XCTAssertTrue(lines()[0].hasPrefix("[CCIOS-213] "))

        NoticeOnset.update(.readOnlyLapsed, active: false, defaults: defaults, log: log)
        NoticeOnset.update(.readOnlyLapsed, active: true, defaults: defaults, log: log)
        XCTAssertEqual(lines().count, 2)
    }

    /// The two lasting banners are user-facing; the lines never shown on screen are not.
    func testMainScreenRule_categories() {
        XCTAssertEqual(Notice.privacyPhraseMissing.category, .storage)
        XCTAssertEqual(Notice.readOnlyLapsed.category, .storage)
        XCTAssertEqual(Notice.takesHeldBack(3).category, .sync)
        XCTAssertEqual(Notice.watermarkPrepareFailed.category, .lifecycle)
        XCTAssertEqual(Notice.libraryOpenFailed("x").category, .lifecycle)
    }

    /// The store the app talks to, so device logs show whether a purchase test is in
    /// Apple's sandbox or Xcode's local test store.
    func testStoreEnvironment_line() {
        XCTAssertEqual(Notice.storeEnvironment("Sandbox").logLine,
                       "[CCIOS-927] Store environment: Sandbox (from the latest Annual transaction)")
        XCTAssertEqual(Notice.storeEnvironment("Sandbox").category, .lifecycle)
        XCTAssertEqual(SubscriptionManager.environmentLabel(nil), "no Annual transaction yet")
        XCTAssertEqual(SubscriptionManager.environmentLabel(.xcode), "Xcode")
        XCTAssertEqual(SubscriptionManager.environmentLabel(.sandbox), "Sandbox")
        XCTAssertEqual(SubscriptionManager.environmentLabel(.production), "Production")
    }

    /// Logged at the first refresh and again only when the store changes, so a first
    /// purchase or redeemed code in the same run still shows which store it went to.
    @MainActor
    func testStoreEnvironment_loggedFirstThenOnlyOnChange() {
        let log = DiagnosticsLog(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("store-env-\(UUID().uuidString).json"))
        let manager = SubscriptionManager()
        manager.noteStoreEnvironment(nil, log: log)
        manager.noteStoreEnvironment(nil, log: log)
        manager.noteStoreEnvironment(.sandbox, log: log)
        manager.noteStoreEnvironment(.sandbox, log: log)
        XCTAssertEqual(log.entries().map(\.message), [
            Notice.storeEnvironment("no Annual transaction yet").logLine,
            Notice.storeEnvironment("Sandbox").logLine,
        ])
    }

    /// One subscription purchase or renewal, so a device log shows the trial, each offer
    /// period and each paid renewal without an App Store Server API key. No transaction id.
    func testSubscriptionTransaction_line() {
        let start = Date(timeIntervalSince1970: 1_795_017_660)      // 2026-11-18 16:01:00 UTC
        let free = SubscriptionHistoryEntry(
            purchased: start, expires: start.addingTimeInterval(3600),
            offerType: "code", offerID: "LAUNCH-FREE-MONTH", paymentMode: "free trial",
            price: 0, currency: "GBP", environment: "Sandbox", revoked: false)
        XCTAssertEqual(Notice.subscriptionTransaction(free).logLine,
                       "[CCIOS-928] Subscription transaction: 2026-11-18 16:01:00 UTC to 2026-11-18 17:01:00 UTC, offer code (LAUNCH-FREE-MONTH, free trial), price 0 GBP, Sandbox")
        XCTAssertEqual(Notice.subscriptionTransaction(free).category, .lifecycle)

        let paid = SubscriptionHistoryEntry(
            purchased: start, expires: nil, offerType: nil, offerID: nil, paymentMode: nil,
            price: Decimal(string: "14.99"), currency: "GBP", environment: "Sandbox", revoked: true)
        XCTAssertEqual(Notice.subscriptionTransaction(paid).logLine,
                       "[CCIOS-928] Subscription transaction: 2026-11-18 16:01:00 UTC to no expiry, no offer, price 14.99 GBP, Sandbox, revoked")
    }

    /// The whole history is written at the first refresh of a run (newest 12, oldest
    /// first), then only transactions not yet written this run, so a renewal that arrives
    /// while the app is open appears once.
    @MainActor
    func testSubscriptionHistory_writesEachTransactionOncePerRun() {
        let log = DiagnosticsLog(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("sub-history-\(UUID().uuidString).json"))
        let manager = SubscriptionManager()
        func entry(_ minute: Double) -> SubscriptionHistoryEntry {
            SubscriptionHistoryEntry(
                purchased: Date(timeIntervalSince1970: 1_795_017_600 + minute * 60), expires: nil,
                offerType: nil, offerID: nil, paymentMode: nil, price: 1, currency: "GBP",
                environment: "Sandbox", revoked: false)
        }
        // 14 transactions, handed over newest first: only the newest 12 are written, oldest first.
        let first = (1...14).reversed().map { (id: UInt64($0), entry: entry(Double($0))) }
        manager.noteSubscriptionHistory(first, log: log)
        XCTAssertEqual(log.entries().map(\.message),
                       (3...14).map { Notice.subscriptionTransaction(entry(Double($0))).logLine })

        // Same history again plus one renewal: only the renewal is written.
        manager.noteSubscriptionHistory(first + [(id: 15, entry: entry(15))], log: log)
        XCTAssertEqual(log.entries().count, 13)
        XCTAssertEqual(log.entries().last?.message, Notice.subscriptionTransaction(entry(15)).logLine)
    }

    func testDisplayText_dropsTheReference() {
        XCTAssertEqual(Notice.displayText(of: "[CCIOS-301] 2 Takes changed on another device."),
                       "2 Takes changed on another device.")
        XCTAssertEqual(Notice.displayText(of: "[CCMOS-104] Sync encountered a problem and will retry."),
                       "Sync encountered a problem and will retry.")
        // Lines recorded before codes existed pass through untouched.
        XCTAssertEqual(Notice.displayText(of: "Take saved"), "Take saved")
        XCTAssertEqual(Notice.displayText(of: "[draft] note"), "[draft] note")
    }

    /// The closed set only holds if nothing writes free text. Scans the app's own source
    /// for the category-and-text form of `record`.
    func testNothingWritesFreeTextToTheLog() throws {
        let appSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CatchlightAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let freeText = try NSRegularExpression(
            pattern: #"DiagnosticsLog\.shared\.record\(\s*\.(sync|storage|conflict|quarantine|lifecycle)\s*,"#)
        var scanned = 0, offenders: [String] = []
        for folder in ["Catchlight", "CatchlightWidgets", "CatchlightShare"] {
            let root = appSource.appendingPathComponent(folder)
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in files where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                scanned += 1
                if freeText.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                    offenders.append(file.lastPathComponent)
                }
            }
        }
        XCTAssertGreaterThan(scanned, 50, "the scan must actually reach the app source")
        XCTAssertEqual(offenders, [], "write a Notice instead: DiagnosticsLog.shared.record(.someNotice)")
    }
}
#endif
