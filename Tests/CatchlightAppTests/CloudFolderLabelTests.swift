//
//  CloudFolderLabelTests.swift
//  CatchlightTests (app module)
//
//  The Cloud Storage sheet shows the chosen folder by its own name, with where it lives under
//  it, never as a path (owner 2026-11-14: the sheet showed "/private/var/mobile/Library/Mobile
//  Documents/com~apple~CloudDocs/Catchlight - iCloud").
//

import XCTest
@testable import Catchlight

final class CloudFolderLabelTests: XCTestCase {

    func testAnICloudDriveFolderShowsItsNameAndICloudDrive() {
        let label = CloudStorageView.folderLabel(
            forPath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Catchlight - iCloud")
        XCTAssertEqual(label.name, "Catchlight - iCloud")
        XCTAssertEqual(label.place, "iCloud Drive")
        XCTAssertEqual(label.spoken, "Catchlight - iCloud, iCloud Drive")
    }

    func testAnotherProvidersFolderShowsItsNameOnly() {
        let label = CloudStorageView.folderLabel(
            forPath: "/private/var/mobile/Containers/Shared/AppGroup/1A2B/File Provider Storage/Catchlight")
        XCTAssertEqual(label.name, "Catchlight")
        XCTAssertNil(label.place)
        XCTAssertEqual(label.spoken, "Catchlight")
    }

    func testNoFolderNameIsAPath() {
        for path in ["/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/A",
                     "/var/mobile/Containers/Shared/AppGroup/X/File Provider Storage/Notes/B"] {
            XCTAssertFalse(CloudStorageView.folderLabel(forPath: path).name.contains("/"), path)
        }
    }
}
