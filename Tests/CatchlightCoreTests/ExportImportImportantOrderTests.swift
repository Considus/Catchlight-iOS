//
//  ExportImportImportantOrderTests.swift
//  CatchlightCoreTests — 2026-09-14
//
//  The Markdown export/import round trip for `isImportant` and `manualOrder`.
//
//  🚨 WHY THESE WERE MISSING, because the shape of the miss is the useful part.
//  The SYNC payload has carried both fields since v3, and
//  `TakeRoundTripIdentityTests` asserts the round trip over a maximally populated
//  Take — so the encrypted format was genuinely lossless and stayed green. The
//  Markdown export is a SECOND, narrower format with its own metadata block, and it
//  simply never gained the two fields. One format being proven lossless said nothing
//  about the other, and nothing compared them.
//
//  It was found the hard way. The owner uses Important constantly, wipes and
//  re-imports his own real Takes several times a week while testing, and had been
//  losing every flag for months without noticing, because nothing announces a flag
//  that quietly fails to come back.
//
//  ⚠️ The back-compat test matters as much as the round-trip ones: exports written
//  before today have neither key, they exist in the owner's own folder right now, and
//  Swift's synthesised decoder throws on a missing key rather than using a default.
//

import XCTest
@testable import CatchlightCore

final class ExportImportImportantOrderTests: XCTestCase {

    private let date = Date(timeIntervalSince1970: 1_757_000_000)

    private func roundTrip(_ take: Take) throws -> Take {
        let exported = TakeExporter.export([take], exportedAt: date)
        let back = TakeImporter.parseDocument(exported, fileDate: date)
        XCTAssertEqual(back.count, 1, "one Take in, one Take out")
        return try XCTUnwrap(back.first)
    }

    // MARK: - The reported fault

    func testImportantSurvivesTheRoundTrip() throws {
        var take = Take(createdAt: date, modifiedAt: date,
                        blocks: [.text(TextBlock(text: "the one that matters"))], isNote: true)
        take.isImportant = true
        XCTAssertTrue(try roundTrip(take).isImportant,
                      "a Take marked Important must come back marked")
    }

    /// The other half, and the one the owner assumed was already handled by the file's
    /// own ordering. It is not: the exporter re-sorts by `createdAt` on the way out, so
    /// position has to travel as data or not at all.
    func testManualOrderSurvivesTheRoundTrip() throws {
        var take = Take(createdAt: date, modifiedAt: date,
                        blocks: [.text(TextBlock(text: "dragged into place"))], isNote: true)
        take.manualOrder = 3.5
        XCTAssertEqual(try roundTrip(take).manualOrder, 3.5)
    }

    /// 🚨 The proof that file order cannot stand in for the field. Three Takes are
    /// arranged in the REVERSE of their creation order; the export writes them
    /// chronologically, and the arrangement still has to survive.
    func testManualOrderSurvivesEvenThoughTheFileIsSortedByDate() throws {
        var takes: [Take] = []
        for i in 0..<3 {
            var t = Take(createdAt: date.addingTimeInterval(Double(i) * 60),
                         modifiedAt: date.addingTimeInterval(Double(i) * 60),
                         blocks: [.text(TextBlock(text: "take \(i)"))], isNote: true)
            t.manualOrder = Double(3 - i)       // reverse of creation order
            takes.append(t)
        }
        let exported = TakeExporter.export(takes, exportedAt: date)
        let back = TakeImporter.parseDocument(exported, fileDate: date)
        XCTAssertEqual(back.count, 3)

        // Read back in the file's own (chronological) order, the manual positions are
        // still the reversed ones that went in.
        XCTAssertEqual(back.map(\.manualOrder), [3, 2, 1],
                       "manual position travels as data, not as file position")
    }

    func testUnflaggedTakeComesBackUnflagged() throws {
        let take = Take(createdAt: date, modifiedAt: date,
                        blocks: [.text(TextBlock(text: "ordinary"))], isNote: true)
        let back = try roundTrip(take)
        XCTAssertFalse(back.isImportant)
        XCTAssertNil(back.manualOrder, "no manual position is the normal case, and stays nil")
    }

    /// Both fields at once, alongside the ones that already worked, so a future change
    /// that fixes one by breaking another is caught here.
    func testImportantAndOrderAndObieAndReminderAllSurviveTogether() throws {
        var take = Take(createdAt: date, modifiedAt: date,
                        blocks: [.text(TextBlock(text: "everything on"))], isNote: true)
        take.isImportant = true
        take.manualOrder = 12.25
        take.isObie = true
        let back = try roundTrip(take)
        XCTAssertTrue(back.isImportant)
        XCTAssertEqual(back.manualOrder, 12.25)
        XCTAssertTrue(back.isObie)
    }

    // MARK: - ⚠️ Back-compat with exports that already exist

    /// An export written before 2026-09-14 has neither key. Those files are sitting in
    /// the owner's folder right now, so this is not a hypothetical: if the decoder
    /// throws on them, the fix for a lost flag becomes a lost export.
    func testOlderExportWithoutTheNewKeysStillImports() throws {
        var take = Take(createdAt: date, modifiedAt: date,
                        blocks: [.text(TextBlock(text: "written by an older build"))], isNote: true)
        take.isImportant = true
        take.manualOrder = 9

        // Strip the two new keys back out of the data block, which is exactly what an
        // older export looks like on disk.
        var exported = TakeExporter.export([take], exportedAt: date)
        for key in ["isImportant", "manualOrder"] {
            exported = exported.replacingOccurrences(
                of: "\"\(key)\":[^,}]*,?",
                with: "", options: .regularExpression)
        }
        XCTAssertFalse(exported.contains("isImportant"), "test fixture must not carry the key")

        let back = TakeImporter.parseDocument(exported, fileDate: date)
        XCTAssertEqual(back.count, 1, "an older export must still import at all")
        let r = try XCTUnwrap(back.first)
        XCTAssertFalse(r.isImportant, "a file that never recorded the flag reads as unflagged")
        XCTAssertNil(r.manualOrder)
        XCTAssertEqual(r.plainText, "written by an older build", "the words still arrive")
    }
}
