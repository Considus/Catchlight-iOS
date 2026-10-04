//
//  NoticeCodeTests.swift
//  CatchlightAppTests
//
//  Pins the diagnostics reference codes: the line format support reads, the display
//  text Notice History shows, and the rule that every log line goes through `Notice`.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight
import CatchlightCore

final class NoticeCodeTests: XCTestCase {

    func testLogLine_isReferenceThenMessage() {
        XCTAssertEqual(Notice.saveFailed.reference, "CCIOS-202")
        XCTAssertEqual(Notice.saveFailed.logLine, "[CCIOS-202] Couldn't save that Take.")
        XCTAssertEqual(Notice.takeDeleted.logLine, "[CCIOS-914] Take deleted")
    }

    /// Same wording, different place: the code is what tells them apart.
    func testSameWording_differentCodes() {
        XCTAssertEqual(Notice.saveFailed.message, Notice.saveInPlaceFailed.message)
        XCTAssertNotEqual(Notice.saveFailed.reference, Notice.saveInPlaceFailed.reference)
    }

    func testCategory_followsTheHundreds() {
        XCTAssertEqual(Notice.syncProblem.category, .sync)
        XCTAssertEqual(Notice.deleteFailed.category, .storage)
        XCTAssertEqual(Notice.conflictsChanged(2).category, .conflict)
        XCTAssertEqual(Notice.takesQuarantined(1).category, .quarantine)
        XCTAssertEqual(Notice.takeSaved.category, .lifecycle)
    }

    /// 950–999 belongs to Catchlight-Core.
    func testNoAppCode_inCoreRange() {
        XCTAssertTrue(NoticeCode.allCases.allSatisfy { !(950...999).contains($0.rawValue) })
    }

    func testDisplayText_dropsTheReference() {
        XCTAssertEqual(Notice.displayText(of: "[CCIOS-301] 2 Takes changed on another device."),
                       "2 Takes changed on another device.")
        XCTAssertEqual(Notice.displayText(of: "[CCMOS-104] Sync encountered a problem and will retry."),
                       "Sync encountered a problem and will retry.")
        // Lines recorded before codes existed pass through untouched.
        XCTAssertEqual(Notice.displayText(of: "Take saved"), "Take saved")
        XCTAssertEqual(Notice.displayText(of: "[draft] note"), "[draft] note")
    }

    /// The closed set only holds if nothing writes free text. Scans the app's own source
    /// for the category-and-text form of `record`.
    func testNothingWritesFreeTextToTheLog() throws {
        let appSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CatchlightAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let freeText = try NSRegularExpression(
            pattern: #"DiagnosticsLog\.shared\.record\(\s*\.(sync|storage|conflict|quarantine|lifecycle)\s*,"#)
        var scanned = 0, offenders: [String] = []
        for folder in ["Catchlight", "CatchlightWidgets", "CatchlightShare"] {
            let root = appSource.appendingPathComponent(folder)
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in files where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                scanned += 1
                if freeText.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                    offenders.append(file.lastPathComponent)
                }
            }
        }
        XCTAssertGreaterThan(scanned, 50, "the scan must actually reach the app source")
        XCTAssertEqual(offenders, [], "write a Notice instead: DiagnosticsLog.shared.record(.someNotice)")
    }
}
#endif
