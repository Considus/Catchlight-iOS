//
//  CloudBookmarkTests.swift
//  CatchlightCoreTests — Task 6.13
//
//  Coverage for the cloud-folder bookmark helpers introduced in Task 6.13:
//    • `URL.bookmarkData(...)` round-trips through `URL(resolvingBookmarkData:)`
//      back to the original path.
//    • Corrupt / unresolvable bookmark data raises an error rather than
//      crashing the resolve path.
//    • `AppModel.friendlyBookmarkErrorMessage(for:)` maps both error variants
//      to user-readable copy.
//
//  We don't drive `UIDocumentPickerViewController` from here (it requires a
//  host UI). Instead we create a real folder in `temporaryDirectory`, ask the
//  system for a bookmark to it, and round-trip — same machinery the production
//  picker uses, exercised without a UI surface.
//

#if canImport(Catchlight)
import XCTest
import CatchlightCore
@testable import Catchlight

final class CloudBookmarkTests: XCTestCase {

    private var tempFolder: URL!

    override func setUpWithError() throws {
        tempFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("catchlight.bookmark.tests.\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempFolder, FileManager.default.fileExists(atPath: tempFolder.path) {
            try? FileManager.default.removeItem(at: tempFolder)
        }
    }

    // MARK: - Round-trip

    func testBookmark_roundTrip_resolvesToSameFolder() throws {
        let bookmark = try tempFolder.bookmarkData(options: [],
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil)
        var stale = false
        let resolved = try URL(resolvingBookmarkData: bookmark,
                               options: [.withoutUI],
                               relativeTo: nil,
                               bookmarkDataIsStale: &stale)
        // Symlink-resolved paths can differ from the original — compare by
        // canonical path rather than the raw URL.
        XCTAssertEqual(resolved.standardizedFileURL.path,
                       tempFolder.standardizedFileURL.path)
        XCTAssertFalse(stale, "Freshly-minted bookmark should not be stale.")
    }

    // MARK: - Corrupt bookmark

    func testResolve_corruptBookmarkData_throws() {
        let garbage = Data("not a real bookmark".utf8)
        var stale = false
        XCTAssertThrowsError(
            try URL(resolvingBookmarkData: garbage,
                    options: [.withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale)
        )
    }

    // MARK: - Wiring health-check helper

    func testCheckCloudBookmarkHealth_noBookmark_returnsNil() {
        // Defaults under the canonical App Group key — clear before asserting
        // so a previous test's state can't leak in.
        UserDefaults(suiteName: AppGroup.identifier)?
            .removeObject(forKey: Wiring.bookmarkDefaultsKey)
        XCTAssertNil(Wiring.checkCloudBookmarkHealth())
    }

    func testCheckCloudBookmarkHealth_corruptBookmark_returnsUnresolvable() throws {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        defer { defaults?.removeObject(forKey: Wiring.bookmarkDefaultsKey) }

        defaults?.set(Data("garbage".utf8), forKey: Wiring.bookmarkDefaultsKey)
        XCTAssertEqual(Wiring.checkCloudBookmarkHealth(), .unresolvable)
    }

    func testCheckCloudBookmarkHealth_validBookmark_returnsNil() throws {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        defer { defaults?.removeObject(forKey: Wiring.bookmarkDefaultsKey) }

        let bookmark = try tempFolder.bookmarkData(options: [],
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil)
        defaults?.set(bookmark, forKey: Wiring.bookmarkDefaultsKey)
        XCTAssertNil(Wiring.checkCloudBookmarkHealth())
    }

    // MARK: - Clear

    func testClearCloudFolderBookmark_removesPersistedData() throws {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        let bookmark = try tempFolder.bookmarkData(options: [],
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil)
        defaults?.set(bookmark, forKey: Wiring.bookmarkDefaultsKey)

        Wiring.clearCloudFolderBookmark()

        XCTAssertNil(defaults?.data(forKey: Wiring.bookmarkDefaultsKey))
    }

    // MARK: - Friendly error mapping

    @MainActor
    func testFriendlyBookmarkErrorMessage_staleMentionsReconfigure() {
        let msg = AppModel.friendlyBookmarkErrorMessage(for: .stale)
        XCTAssertTrue(msg.localizedCaseInsensitiveContains("Cloud Storage"),
                      "Stale copy should point the user at Settings → Cloud Storage. Got: \(msg)")
    }

    @MainActor
    func testFriendlyBookmarkErrorMessage_unresolvableMentionsReconfigure() {
        let msg = AppModel.friendlyBookmarkErrorMessage(for: .unresolvable)
        XCTAssertTrue(msg.localizedCaseInsensitiveContains("Cloud Storage"),
                      "Unresolvable copy should point the user at Settings → Cloud Storage. Got: \(msg)")
    }

    @MainActor
    func testReportBookmarkError_setsLastSyncErrorMessage() {
        let app = AppModel.preview(store: InMemoryTakeStore(), onboarded: true)
        XCTAssertNil(app.lastSyncError)
        app.reportBookmarkError(.stale)
        XCTAssertEqual(app.lastSyncError,
                       AppModel.friendlyBookmarkErrorMessage(for: .stale))
    }
}
#endif
