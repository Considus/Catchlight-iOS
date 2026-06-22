//
//  LinkDetectorTests.swift
//  CatchlightCoreTests — clickable links in Take bodies (owner 2026-06-22)
//
//  Pins the two-pass detection: schemed/www URLs via NSDataDetector, plus bare
//  domains (assumed https://) gated by a curated TLD set so notes content like
//  "readme.md" or "Mr.Smith" never becomes a link.
//

import XCTest
@testable import CatchlightCore

final class LinkDetectorTests: XCTestCase {

    private func urls(_ text: String) -> [String] {
        LinkDetector.detect(in: text).map { $0.url.absoluteString }
    }

    private func matchedSubstrings(_ text: String) -> [String] {
        LinkDetector.detect(in: text).map { String(text[$0.range]) }
    }

    // MARK: - Schemed / www

    func testSchemedURL_isDetected() {
        XCTAssertEqual(urls("see https://catchlight.app today"),
                       ["https://catchlight.app"])
    }

    func testWWWURL_isDetectedWithScheme() {
        // NSDataDetector resolves www. links with an http(s) scheme.
        let result = LinkDetector.detect(in: "go to www.catchlight.app")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first.map { String("go to www.catchlight.app"[$0.range]) },
                       "www.catchlight.app")
        XCTAssertNotNil(result.first?.url.scheme)
    }

    // MARK: - Bare domains (assumed https://)

    func testBareDomain_commonTLD_assumesHTTPS() {
        XCTAssertEqual(urls("visit catchlight.app now"),
                       ["https://catchlight.app"])
    }

    func testBareDomain_withPath_keepsPath() {
        XCTAssertEqual(urls("catchlight.app/privacy is the page"),
                       ["https://catchlight.app/privacy"])
        XCTAssertEqual(matchedSubstrings("catchlight.app/privacy is the page"),
                       ["catchlight.app/privacy"])
    }

    func testBareDomain_multiple() {
        XCTAssertEqual(urls("a.com and b.org"),
                       ["https://a.com", "https://b.org"])
    }

    // MARK: - Precision: must NOT link

    func testFileLikeTokens_areNotLinked() {
        XCTAssertTrue(urls("see readme.md and config.json and notes.txt").isEmpty)
    }

    func testAbbreviationsAndNames_areNotLinked() {
        XCTAssertTrue(urls("e.g. something").isEmpty)
        XCTAssertTrue(urls("Mr.Smith called").isEmpty)   // uppercase → not a domain
        XCTAssertTrue(urls("version 3.5 shipped").isEmpty)
    }

    func testEmailDomain_isNotLinkedAsWebsite() {
        // The lookbehind stops the domain half of an email becoming an http link.
        XCTAssertTrue(urls("mail me at hi@catchlight.app").allSatisfy { !$0.hasPrefix("https://catchlight.app") })
    }

    // MARK: - Empty

    func testEmptyAndPlainText_returnNothing() {
        XCTAssertTrue(LinkDetector.detect(in: "").isEmpty)
        XCTAssertTrue(LinkDetector.detect(in: "just some ordinary words here").isEmpty)
    }
}
