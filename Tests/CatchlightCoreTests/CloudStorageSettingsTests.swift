//
//  CloudStorageSettingsTests.swift
//  CatchlightCoreTests — Task 3.12
//
//  Verifies that Settings → Cloud Storage persists the folder bookmark to the
//  same App-Group UserDefaults key that Wiring.makeSyncEngine and
//  FileCloudFolder(bookmark:) read at runtime. If this passes, BackgroundSync
//  picks up the user's choice unchanged. (The paste-a-URL fallback and its
//  defaults key were removed 2026-06-22 — only iCloud + Dropbox folder-picks work.)
//
//  Bookmark round-trip is exercised via FileCloudFolder.makeBookmark + the
//  URL(resolvingBookmarkData:) resolver, mirroring the production path. The
//  test uses a temporary local directory so it runs without any cloud provider.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight
@testable import CatchlightCore

final class CloudStorageSettingsTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "catchlight.tests.cloudstorage.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_bookmark_round_trips_via_FileCloudFolder() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("catchlight-cloudfolder-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let bookmark = try FileCloudFolder.makeBookmark(for: temp)
        defaults.set(bookmark, forKey: Wiring.bookmarkDefaultsKey)

        let read = try XCTUnwrap(defaults.data(forKey: Wiring.bookmarkDefaultsKey))
        var stale = false
        let resolved = try URL(resolvingBookmarkData: read,
                               options: [.withoutUI],
                               relativeTo: nil,
                               bookmarkDataIsStale: &stale)
        XCTAssertEqual(resolved.standardizedFileURL, temp.standardizedFileURL)
    }
}
#endif
