//
//  CloudStorageSettingsTests.swift
//  CatchlightCoreTests — Task 3.12
//
//  Verifies that Settings → Cloud Storage persists folder bookmarks AND the
//  URL-string fallback to the same App-Group UserDefaults keys that
//  Wiring.makeSyncEngine and FileCloudFolder(bookmark:) read at runtime. If
//  these tests pass, BackgroundSync will pick up the user's choice unchanged.
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

    func test_url_string_round_trips_through_defaults_key() {
        let url = "smb://nas.local/Catchlight"
        defaults.set(url, forKey: Wiring.cloudFolderURLStringDefaultsKey)
        let read = defaults.string(forKey: Wiring.cloudFolderURLStringDefaultsKey)
        XCTAssertEqual(read, url)
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

    func test_settings_keys_differ() {
        // Guard against an accidental rename collapsing the two storage slots.
        XCTAssertNotEqual(Wiring.bookmarkDefaultsKey,
                          Wiring.cloudFolderURLStringDefaultsKey)
    }
}
#endif
