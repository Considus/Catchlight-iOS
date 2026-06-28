//
//  DiagnosticsLogTests.swift
//  CatchlightCoreTests
//
//  The content-free diagnostics log (D-085): append + cap, user-facing filtering (newest-first),
//  plain-text export, clear, and persistence across instances.
//

import XCTest
@testable import CatchlightCore

final class DiagnosticsLogTests: XCTestCase {

    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("diag-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        super.tearDown()
    }

    func testRecord_thenEntries_oldestFirst() {
        let log = DiagnosticsLog(fileURL: fileURL)
        log.record(.storage, "Couldn't save that Take.")
        log.record(.sync, "Sync paused — another device is syncing.")
        let entries = log.entries()
        XCTAssertEqual(entries.map(\.message),
                       ["Couldn't save that Take.", "Sync paused — another device is syncing."])
        XCTAssertEqual(entries.map(\.category), [.storage, .sync])
    }

    func testCap_keepsNewestMaxEntries() {
        let log = DiagnosticsLog(fileURL: fileURL)
        for i in 0..<(DiagnosticsLog.maxEntries + 25) { log.record(.lifecycle, "event \(i)") }
        let entries = log.entries()
        XCTAssertEqual(entries.count, DiagnosticsLog.maxEntries, "older entries roll off")
        XCTAssertEqual(entries.first?.message, "event 25", "the newest window is kept")
        XCTAssertEqual(entries.last?.message, "event \(DiagnosticsLog.maxEntries + 24)")
    }

    func testUserFacingEntries_excludeLifecycle_newestFirst() {
        let log = DiagnosticsLog(fileURL: fileURL)
        log.record(.lifecycle, "launched")          // internal — hidden from Notice History
        log.record(.storage, "Couldn't load your Takes.")
        log.record(.quarantine, "1 Take couldn't be verified and was skipped.")
        let shown = log.userFacingEntries()
        XCTAssertEqual(shown.map(\.message),
                       ["1 Take couldn't be verified and was skipped.", "Couldn't load your Takes."],
                       "user-facing only, newest-first")
    }

    func testExportText_includesCategoryAndMessage() {
        let log = DiagnosticsLog(fileURL: fileURL)
        log.record(.sync, "A sync error occurred.")
        let text = log.exportText()
        XCTAssertTrue(text.contains("[sync]"))
        XCTAssertTrue(text.contains("A sync error occurred."))
    }

    func testExportText_empty_isReadable() {
        XCTAssertEqual(DiagnosticsLog(fileURL: fileURL).exportText(), "No diagnostics recorded.")
    }

    func testPersistsAcrossInstances() {
        DiagnosticsLog(fileURL: fileURL).record(.conflict, "2 Takes changed on another device.")
        let reloaded = DiagnosticsLog(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries().map(\.message), ["2 Takes changed on another device."])
    }

    func testClear_emptiesTheLog() {
        let log = DiagnosticsLog(fileURL: fileURL)
        log.record(.storage, "x")
        log.clear()
        XCTAssertTrue(log.entries().isEmpty)
    }
}
