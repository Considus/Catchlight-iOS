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

    /// `maxEntries` is the USER-FACING budget, so cap it with a user-facing category. This test used
    /// to drive it with `.lifecycle` back when all categories shared one 200-entry pool; breadcrumbs
    /// now have their own (larger) budget so they can never evict a notice — see
    /// `testBreadcrumbsCannotEvictUserFacingNotices`. Same intent: oldest roll off, newest kept.
    func testCap_keepsNewestMaxEntries() {
        let log = DiagnosticsLog(fileURL: fileURL)
        for i in 0..<(DiagnosticsLog.maxEntries + 25) { log.record(.sync, "event \(i)") }
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

    /// Notice History's Clear removes only what it SHOWS (2026-07-01): the
    /// lifecycle breadcrumbs survive so "Export diagnostics" still has content
    /// for a bug report after the user tidies their notices.
    func testClearUserFacing_keepsLifecycleBreadcrumbs() {
        let log = DiagnosticsLog(fileURL: fileURL)
        log.record(.sync, "Sync paused.")
        log.record(.lifecycle, "app became active")
        log.record(.conflict, "1 Take changed on another device.")

        log.clearUserFacing()

        XCTAssertTrue(log.userFacingEntries().isEmpty, "the notices list must empty")
        XCTAssertEqual(log.entries().map(\.category), [.lifecycle],
                       "breadcrumbs must survive for the diagnostics export")
    }

    // MARK: - Budgets / retention (owner 2026-07-16)

    /// THE regression this whole design exists to prevent: breadcrumbs are frequent and notices are
    /// rare, so a SHARED pool lets `lifecycle` evict every notice and Notice History reads empty.
    func testBreadcrumbsCannotEvictUserFacingNotices() {
        let log = DiagnosticsLog(fileURL: fileURL)
        log.record(.sync, "sync notice")
        for i in 0..<(DiagnosticsLog.maxLifecycleEntries * 2) { log.record(.lifecycle, "crumb \(i)") }

        let entries = log.entries()
        XCTAssertTrue(entries.contains { $0.category == .sync && $0.message == "sync notice" },
                      "a flood of breadcrumbs must never evict a user-facing notice")
        XCTAssertEqual(entries.filter { !$0.category.isUserFacing }.count,
                       DiagnosticsLog.maxLifecycleEntries, "breadcrumbs keep their own budget")
    }

    func testEachClassKeepsItsOwnBudget() {
        let log = DiagnosticsLog(fileURL: fileURL)
        for i in 0..<(DiagnosticsLog.maxEntries + 50) { log.record(.sync, "notice \(i)") }
        for i in 0..<(DiagnosticsLog.maxLifecycleEntries + 50) { log.record(.lifecycle, "crumb \(i)") }

        let entries = log.entries()
        XCTAssertEqual(entries.filter { $0.category.isUserFacing }.count, DiagnosticsLog.maxEntries)
        XCTAssertEqual(entries.filter { !$0.category.isUserFacing }.count, DiagnosticsLog.maxLifecycleEntries)
    }

    /// Age evicts regardless of how few entries there are — a light user's log must not span months.
    func testTrimDropsEntriesOlderThanMaxAge() {
        let now = Date()
        let old = DiagnosticEntry(timestamp: now.addingTimeInterval(-31 * 24 * 3600),
                                  category: .sync, message: "ancient")
        let fresh = DiagnosticEntry(timestamp: now, category: .sync, message: "recent")

        let kept = DiagnosticsLog.trim([old, fresh], now: now)
        XCTAssertEqual(kept.map(\.message), ["recent"], "anything past the age ceiling is dropped")
    }

    /// The byte ceiling bounds SIZE, which a count cannot: one chatty entry and the file runs away.
    func testTrimEnforcesByteCeiling() {
        let fat = String(repeating: "x", count: 4_000)
        let entries = (0..<200).map { _ in DiagnosticEntry(category: .lifecycle, message: fat) }

        let kept = DiagnosticsLog.trim(entries)
        let size = (try? JSONEncoder().encode(kept).count) ?? .max
        XCTAssertLessThanOrEqual(size, DiagnosticsLog.maxBytes, "oldest drop until the file fits")
        XCTAssertFalse(kept.isEmpty, "the newest entries survive")
    }

    /// Auto-delete may only TIGHTEN retention. It defaults to Never, so it cannot be the sole bound
    /// — and Monthly/Annually are longer than we ever need.
    func testEffectiveMaxAgeTakesTheShorterOfTheTwo() {
        XCTAssertEqual(DiagnosticsLog.effectiveMaxAge(autoDeleteWindow: nil),
                       DiagnosticsLog.maxAge, "Never ⇒ our own ceiling, never unbounded")
        XCTAssertEqual(DiagnosticsLog.effectiveMaxAge(autoDeleteWindow: 24 * 3600),
                       24 * 3600, "a tighter window wins")
        XCTAssertEqual(DiagnosticsLog.effectiveMaxAge(autoDeleteWindow: 365 * 24 * 3600),
                       DiagnosticsLog.maxAge, "a longer window is capped at ours")
    }

    // MARK: - Unexpected-termination detection

    func testUnexpectedTerminationIsDetectedAndIsNotUserFacing() {
        let suite = "diag-crash-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // Run 1: launches, then dies without an orderly exit (no markCleanExit).
        let first = DiagnosticsLog(fileURL: fileURL)
        XCTAssertFalse(first.recordLaunch(defaults: defaults, build: "1.0 (abc123)",
                                          systemVersion: "26.3.1", deviceModel: "iPhone17,1"),
                       "a first launch has nothing to report")

        // Run 2: the flag is still set ⇒ the previous run crashed.
        let second = DiagnosticsLog(fileURL: fileURL)
        XCTAssertTrue(second.recordLaunch(defaults: defaults, build: "1.0 (abc123)",
                                          systemVersion: "26.3.1", deviceModel: "iPhone17,1"))

        let entries = second.entries()
        let crash = entries.first { $0.message.contains("ended unexpectedly") }
        XCTAssertNotNil(crash, "the termination is recorded")
        XCTAssertEqual(crash?.category, .lifecycle,
                       "log-only (owner): lifecycle never reaches Notice History")
        XCTAssertTrue(crash?.message.contains("abc123") == true, "names the exact build that died")
        XCTAssertTrue(entries.filter { $0.category.isUserFacing }.isEmpty,
                      "nothing user-facing is produced")
    }

    func testCleanExitMeansTheNextLaunchReportsNothing() {
        let suite = "diag-clean-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = DiagnosticsLog(fileURL: fileURL)
        first.recordLaunch(defaults: defaults, build: "1.0", systemVersion: "26.3.1", deviceModel: "iPhone17,1")
        first.markCleanExit(defaults: defaults)

        let second = DiagnosticsLog(fileURL: fileURL)
        XCTAssertFalse(second.recordLaunch(defaults: defaults, build: "1.0",
                                           systemVersion: "26.3.1", deviceModel: "iPhone17,1"),
                       "an orderly background exit must not look like a crash")
    }
}
