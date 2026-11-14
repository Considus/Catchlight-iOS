//
//  PrivacyPhraseTermTests.swift
//  CatchlightTests (app module)
//
//  The app names the 12 words "Privacy phrase", capital P, everywhere a person reads it.
//  No English string in any catalog may call them "privacy phrase" in lower case or a
//  "recovery phrase". The test reads the catalogs, so it holds the text the app shows.
//

import XCTest

final class PrivacyPhraseTermTests: XCTestCase {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .resolvingSymlinksInPath()
    }

    private let catalogs = [
        "Catchlight/Resources/Localizable.xcstrings",
        "Catchlight/Resources/AppShortcuts.xcstrings",
        "Catchlight/Resources/InfoPlist.xcstrings",
        "CatchlightWidgets/Localizable.xcstrings",
        "CatchlightShare/Localizable.xcstrings",
    ]

    func testEveryEnglishStringSaysPrivacyPhrase() throws {
        var checked = 0
        var offending: [String] = []
        for path in catalogs {
            let url = repoRoot.appendingPathComponent(path)
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            let strings = try XCTUnwrap(json?["strings"] as? [String: Any], "\(path) has no strings")
            for key in strings.keys {
                checked += 1
                if key.contains("privacy phrase") || key.localizedCaseInsensitiveContains("recovery phrase") {
                    offending.append(key)
                }
            }
        }
        XCTAssertGreaterThan(checked, 500, "expected to read every catalog's strings")
        XCTAssertEqual(offending, [], "strings that should say Privacy phrase")
    }
}
