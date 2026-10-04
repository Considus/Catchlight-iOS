//
//  ErrorStateTests.swift
//  CatchlightCoreTests
//
//  Task 3.9: Error and edge-case states — verifies the state machine that drives
//  the non-blocking notice strips on the timeline:
//    • DailiesViewModel.clearError() clears the surfaced storage error
//    • AppModel.friendlySyncErrorMessage(for:) maps the small set of known errors
//      to the expected user-facing strings (and drops the "local-only" case)
//    • AppModel.reportQuarantined(_:) counts distinct Takes
//
//  These tests reach into the iOS app target, so the file is gated by
//  `#if canImport(Catchlight)` and runs inside the iOS test bundle only.
//

#if canImport(Catchlight)
import XCTest
@testable import CatchlightCore
@testable import Catchlight

@MainActor
final class ErrorStateTests: XCTestCase {

    // MARK: - DailiesViewModel.clearError

    /// A failing store operation surfaces `lastError`; `clearError()` must wipe it.
    func testClearError_resetsLastErrorAfterFailingDelete() throws {
        // The InMemoryTakeStore returns notFound on delete of an unknown id —
        // exactly the surface that DailiesViewModel.delete() catches and maps to
        // `lastError`.
        let store = InMemoryTakeStore()
        let vm = DailiesViewModel(store: store)
        XCTAssertNil(vm.lastError)

        vm.delete(Take(blocks: [.textLine("ghost — never inserted")]))
        XCTAssertNotNil(vm.lastError, "Deleting an unknown Take should surface lastError")

        vm.clearError()
        XCTAssertNil(vm.lastError)
    }

    // MARK: - AppModel.friendlySyncErrorMessage

    func testSyncErrorMappedCorrectly_manifestSignatureInvalid() {
        let message = AppModel.friendlySyncErrorMessage(for: SyncError.manifestSignatureInvalid)
        XCTAssertEqual(
            message,
            "Sync paused. Your cloud data looks unexpected. No changes were made locally."
        )
    }

    func testSyncErrorMappedCorrectly_lockHeldByOtherDevice() {
        let lock = SyncLockError.heldByOtherDevice(holder: UUID(), retryAfterSeconds: 45)
        let message = AppModel.friendlySyncErrorMessage(for: lock)
        XCTAssertEqual(
            message,
            "Another device is syncing. Catchlight will retry automatically."
        )
    }

    func testSyncErrorMappedCorrectly_noCloudFolderConfiguredIsSilent() {
        // Local-only mode is not an error and must NOT surface a strip.
        let message = AppModel.friendlySyncErrorMessage(for: SyncError.noCloudFolderConfigured)
        XCTAssertNil(message)
    }

    func testSyncErrorMappedCorrectly_unknownErrorFallsBack() {
        struct UnknownError: Error {}
        let message = AppModel.friendlySyncErrorMessage(for: UnknownError())
        XCTAssertEqual(message, "Sync encountered a problem and will retry.")
    }

    func testReportSyncError_skipsLocalOnlyCase() {
        let app = AppModel.preview(store: InMemoryTakeStore(), onboarded: true)
        XCTAssertNil(app.lastSyncError)

        app.reportSyncError(SyncError.noCloudFolderConfigured)
        XCTAssertNil(app.lastSyncError, "Local-only mode must not surface a strip")

        app.reportSyncError(SyncError.manifestSignatureInvalid)
        XCTAssertNotNil(app.lastSyncError)

        app.clearSyncError()
        XCTAssertNil(app.lastSyncError)
    }

    /// Takes held back after a long time offline show in the sync strip (owner 2026-10-04).
    func testReportHeldBack_showsInTheSyncStrip() {
        let app = AppModel.preview(store: InMemoryTakeStore(), onboarded: true)
        app.reportHeldBack(0)
        XCTAssertNil(app.lastSyncError, "nothing held back, nothing to say")
        app.reportHeldBack(2)
        XCTAssertEqual(app.lastSyncError, Notice.takesHeldBack(2).message)
    }

    // MARK: - AppModel.reportQuarantined

    func testQuarantineCountIncrement() {
        let app = AppModel.preview(store: InMemoryTakeStore(), onboarded: true)
        XCTAssertEqual(app.quarantinedCount, 0)

        app.reportQuarantined([UUID(), UUID(), UUID()])
        XCTAssertEqual(app.quarantinedCount, 3)

        // A subsequent pass adds any NEW Takes — strips reflect every distinct
        // Take the user hasn't dismissed yet.
        app.reportQuarantined([UUID()])
        XCTAssertEqual(app.quarantinedCount, 4)

        // Empty pass is a no-op.
        app.reportQuarantined([])
        XCTAssertEqual(app.quarantinedCount, 4)

        app.clearQuarantineNotice()
        XCTAssertEqual(app.quarantinedCount, 0)
    }

    /// Every pull re-reports a Take whose cloud copy still fails, so the same Take must not be
    /// counted again. Observed on device: one sync pass after another took the strip from
    /// "3 Takes" to "6 Takes" within a minute, with three Takes in the store.
    func testQuarantineCount_sameTakeReportedAgain_isNotCountedTwice() {
        let app = AppModel.preview(store: InMemoryTakeStore(), onboarded: true)
        let a = UUID(), b = UUID(), c = UUID()

        app.reportQuarantined([a, b, c])
        app.reportQuarantined([a, b, c])
        XCTAssertEqual(app.quarantinedCount, 3)

        // A new Take joining the set still counts.
        app.reportQuarantined([a, UUID()])
        XCTAssertEqual(app.quarantinedCount, 4)

        // Dismissing clears the set, so a Take that is still failing raises the strip again.
        app.clearQuarantineNotice()
        app.reportQuarantined([a])
        XCTAssertEqual(app.quarantinedCount, 1)
    }
}
#endif
