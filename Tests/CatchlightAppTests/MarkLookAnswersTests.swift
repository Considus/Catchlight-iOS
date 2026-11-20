//
//  MarkLookAnswersTests.swift
//  CatchlightTests (app module)
//
//  Three small look decisions (owner, 2026-11-20):
//  - With Reduce Motion on, the Sequence filter chips fade in place, with no slide.
//    With it off they fade and slide up from the toolbar, as before.
//  - About's licences heading reads "Open source licences" (sentence case), in every language.
//  The conflict card's side label is held by SentenceCaseLabelTests.
//

import XCTest
@testable import Catchlight

final class MarkLookAnswersTests: XCTestCase {

    // MARK: Sequence chips

    func testChips_reduceMotionOn_fadeOnly() {
        XCTAssertEqual(DailiesToolbar.chipsEntrance(reduceMotion: true), .fade)
    }

    func testChips_reduceMotionOff_fadeAndSlide_unchanged() {
        XCTAssertEqual(DailiesToolbar.chipsEntrance(reduceMotion: false), .fadeAndSlide)
    }

    // MARK: Licences heading

    private var catalog: [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Catchlight/Resources/Localizable.xcstrings")
        do {
            let data = try Data(contentsOf: url)
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return root?["strings"] as? [String: Any] ?? [:]
        } catch {
            XCTFail("could not read the catalog: \(error)")
            return [:]
        }
    }

    private func translations(_ key: String) -> [String: String] {
        let entry = catalog[key] as? [String: Any]
        let locs = entry?["localizations"] as? [String: Any] ?? [:]
        var out: [String: String] = [:]
        for (lang, value) in locs {
            if let unit = (value as? [String: Any])?["stringUnit"] as? [String: Any],
               let text = unit["value"] as? String { out[lang] = text }
        }
        return out
    }

    func testLicencesHeading_isSentenceCase_inEnglish() {
        XCTAssertNotNil(catalog["Open source licences"], "the heading's key is the English text")
        XCTAssertNil(catalog["Open Source Licences"], "the title-case key is gone")
    }

    func testLicencesHeading_keepsAllEighteenTranslations() {
        XCTAssertEqual(translations("Open source licences").count, 18)
    }

    func testLicencesHeading_titleCaseTranslations_becomeSentenceCase() {
        let text = translations("Open source licences")
        XCTAssertEqual(text["da"], "Open source-licenser")
        XCTAssertEqual(text["tr"], "Açık kaynak lisansları")
        XCTAssertEqual(text["de"], "Open-Source-Lizenzen", "German capitalises nouns: unchanged")
    }
}
