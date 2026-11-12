//
//  CloudFolderCheckTests.swift
//  CatchlightAppTests — the check that the chosen cloud folder still opens, run each time
//  the app comes to the front.
//
//  On the owner's iPhone the folder's bookmark sometimes fails to resolve when the app returns
//  after a while away, then resolves again seconds later: the sync that follows opened the same
//  bookmark and succeeded 13 to 31 seconds after each "Your cloud folder couldn't be opened"
//  (diagnostics, 2026-11-10 and 11). These tests hold the strip back for a failure that clears
//  on a re-check, and keep it for one that doesn't.
//

#if canImport(Catchlight)
import XCTest
import CatchlightCore
@testable import Catchlight

@MainActor
final class CloudFolderCheckTests: XCTestCase {

    /// Hands out one result per call, then repeats the last.
    private final class Results {
        var queue: [Wiring.CloudBookmarkError?]
        private(set) var calls = 0
        init(_ queue: [Wiring.CloudBookmarkError?]) { self.queue = queue }
        func next() -> Wiring.CloudBookmarkError? {
            calls += 1
            return queue.count > 1 ? queue.removeFirst() : queue[0]
        }
    }

    private let unresolvable = "Your cloud folder couldn't be opened. Open Settings → Cloud Storage to choose a new one."

    func testFailureThatClearsOnARecheck_showsNoStrip() async {
        let app = AppModel.preview(store: InMemoryTakeStore(), onboarded: true)
        let results = Results([.unresolvable, .unresolvable, nil])
        await app.verifyCloudFolder(check: results.next, sleep: { _ in })
        XCTAssertNil(app.lastSyncError, "A folder that opens on a re-check is not broken.")
        XCTAssertEqual(results.calls, 3)
    }

    func testFailureOnEveryCheck_showsTheStrip() async {
        let app = AppModel.preview(store: InMemoryTakeStore(), onboarded: true)
        let results = Results([.unresolvable])
        await app.verifyCloudFolder(check: results.next, sleep: { _ in })
        XCTAssertEqual(app.lastSyncError, unresolvable)
    }

    func testStaleOnEveryCheck_showsTheStaleStrip() async {
        let app = AppModel.preview(store: InMemoryTakeStore(), onboarded: true)
        await app.verifyCloudFolder(check: { .stale }, sleep: { _ in })
        XCTAssertEqual(app.lastSyncError,
                       "Your cloud folder is no longer available. Open Settings → Cloud Storage to re-pick it.")
    }

    func testHealthyFolder_isCheckedOnceAndShowsNoStrip() async {
        let app = AppModel.preview(store: InMemoryTakeStore(), onboarded: true)
        let results = Results([nil])
        await app.verifyCloudFolder(check: results.next, sleep: { _ in })
        XCTAssertNil(app.lastSyncError)
        XCTAssertEqual(results.calls, 1)
    }

    /// A newer check (the app came to the front again) cancels this one: it must not report.
    func testCancelledCheck_showsNoStrip() async {
        let app = AppModel.preview(store: InMemoryTakeStore(), onboarded: true)
        await app.verifyCloudFolder(check: { .unresolvable },
                                    sleep: { _ in throw CancellationError() })
        XCTAssertNil(app.lastSyncError)
    }

    /// The re-checks span about half a minute: on the owner's phone the folder opened again
    /// within 13 to 31 seconds each time.
    func testRetriesSpanAboutHalfAMinute() {
        let total = AppModel.cloudFolderRetryDelays.reduce(Duration.zero, +)
        XCTAssertGreaterThanOrEqual(total, .seconds(30))
        XCTAssertLessThanOrEqual(total, .seconds(45))
    }
}
#endif
