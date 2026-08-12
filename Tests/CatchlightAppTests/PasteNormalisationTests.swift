//
//  PasteNormalisationTests.swift
//  CatchlightAppTests — paste line break (owner 2026-08-11)
//
//  The owner reported that pasting onto a line below another added an unwanted line break.
//  The editor never inserted one: `shouldChangeTextIn` returned true unchanged and
//  `textViewDidChange` copies the text view verbatim. The newline arrives ON THE CLIPBOARD —
//  copying a line out of Safari/Mail/Notes carries its trailing newline — so it is trimmed at
//  the boundary instead.
//
//  These pin the two properties that make that safe: a single Return still works, and the
//  internal shape of a deliberate multi-paragraph paste is preserved.
//
//  iOS-only — gated on `canImport(Catchlight)`.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

final class PasteNormalisationTests: XCTestCase {

    private func normalise(_ s: String) -> String {
        BlockEditorViewController.normalisedPaste(s)
    }

    // MARK: - The reported bug

    func testTrailingNewline_isTrimmed() {
        XCTAssertEqual(normalise("line two\n"), "line two")
    }

    func testSeveralTrailingNewlines_areAllTrimmed() {
        XCTAssertEqual(normalise("line two\n\n\n"), "line two")
    }

    func testTrailingCarriageReturn_isTrimmed() {
        XCTAssertEqual(normalise("line two\r\n"), "line two")
    }

    // MARK: - Leading newlines (device round 2 — this is the one the owner actually hit)

    func testLeadingNewline_isTrimmed() {
        XCTAssertEqual(normalise("\nline two"), "line two")
    }

    func testSeveralLeadingNewlines_areAllTrimmed() {
        XCTAssertEqual(normalise("\n\n\nline two"), "line two")
    }

    func testLeadingCarriageReturn_isTrimmed() {
        XCTAssertEqual(normalise("\r\nline two"), "line two")
    }

    func testBothEnds_areTrimmedTogether() {
        XCTAssertEqual(normalise("\nline two\n"), "line two")
    }

    // MARK: - What must NOT change

    /// THE GUARD THAT MATTERS. Return in a prose row inserts a bare "\n" through this same
    /// delegate — trimming it would make the Return key dead.
    func testSingleNewline_isUntouched() {
        XCTAssertEqual(normalise("\n"), "\n")
    }

    func testSingleCharacter_isUntouched() {
        XCTAssertEqual(normalise("a"), "a")
    }

    func testInternalNewlines_arePreserved() {
        XCTAssertEqual(normalise("para one\n\npara two"), "para one\n\npara two")
    }

    func testInternalNewlinesPreserved_whileTrailingTrimmed() {
        XCTAssertEqual(normalise("para one\n\npara two\n"), "para one\n\npara two")
    }

    func testTrailingSpaces_areLeftAlone() {
        // Only newlines are dropped; trimming spaces mid-typing would fight the user.
        XCTAssertEqual(normalise("line two  "), "line two  ")
    }

    func testPlainPaste_isUnchanged() {
        XCTAssertEqual(normalise("a whole pasted sentence"), "a whole pasted sentence")
    }

    func testEmpty_isUnchanged() {
        // A deletion reports empty replacement text through the same delegate.
        XCTAssertEqual(normalise(""), "")
    }
}
#endif
