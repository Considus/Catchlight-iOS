//
//  ImportDecodeTests.swift
//  CatchlightAppTests — 2026-07-04 testability follow-up to the mid-point remediation
//
//  Pins the import text-decode fallback added in PR #102: non-UTF-8 files (UTF-16
//  from Windows Notepad, Latin-1) were previously counted "skipped" with no
//  explanation. The decode chain (UTF-8 → NSString detection → Latin-1 last
//  resort) was split out of `plainText(of:)` into the pure `decodeText` so it is
//  testable without a real file on disk.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

@MainActor
final class ImportDecodeTests: XCTestCase {

    func testUTF8_decodes() {
        let data = Data("héllo — world".utf8)
        XCTAssertEqual(ImportCoordinator.decodeText(data, isRTF: false), "héllo — world")
    }

    /// UTF-16 (with BOM, as Windows Notepad writes) is invalid UTF-8; the NSString
    /// detection path must still decode it rather than skip the file.
    func testUTF16WithBOM_decodes() throws {
        let data = try XCTUnwrap("hello".data(using: .utf16))   // includes the BOM
        XCTAssertEqual(ImportCoordinator.decodeText(data, isRTF: false), "hello")
    }

    /// A byte stream that's invalid UTF-8 but valid Latin-1 must DECODE (not be
    /// silently skipped). `0xE9` is "é" in Latin-1 and an illegal standalone UTF-8
    /// lead byte; the leading ASCII "caf" survives under any fallback encoding.
    func testNonUTF8Bytes_decodeRatherThanSkip() {
        let data = Data([0x63, 0x61, 0x66, 0xE9])   // "caf" + 0xE9
        let decoded = ImportCoordinator.decodeText(data, isRTF: false)
        XCTAssertNotNil(decoded, "a non-UTF-8 text file must decode, not be skipped")
        XCTAssertEqual(decoded?.hasPrefix("caf"), true)
    }

    /// RTF decodes through NSAttributedString — control words stripped, words kept.
    func testRTF_stripsControlWords() {
        let rtf = Data(#"{\rtf1\ansi\ansicpg1252 hello world}"#.utf8)
        let decoded = ImportCoordinator.decodeText(rtf, isRTF: true)
        XCTAssertEqual(decoded?.contains("hello world"), true)
    }
}
#endif
