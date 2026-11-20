//
//  SentenceCaseButtonTests.swift
//  CatchlightTests (app module)
//
//  Buttons and Settings rows are in sentence case, like the rows beside them ("Lock after",
//  "Report an issue"). Page headings, Apple's feature names and document names keep their
//  capitals and are not listed here. The English is the catalog key, so the test reads the
//  catalog: the sentence-case key is there with every translation, and the Title Case key is
//  gone. Turkish and Brazilian Portuguese had copied the English capitals; they follow too.
//

import XCTest

final class SentenceCaseButtonTests: XCTestCase {

    /// Each button or row, as the old Title Case key and the sentence-case key it becomes.
    private let renamed: [(old: String, new: String)] = [
        ("Try Again", "Try again"),
        ("Redeem Code", "Redeem code"),
        ("Restore Purchases", "Restore purchases"),
        ("Enable Notifications", "Enable notifications"),
        ("Sync Now", "Sync now"),
        ("Manage Subscription", "Manage subscription"),
        ("Delete Series", "Delete series"),
        ("Delete This Occurrence", "Delete this occurrence"),
        ("Snooze Duration", "Snooze duration"),
        ("Auto-Delete (exc. notes)", "Auto-delete (exc. notes)"),
    ]

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

    private func translations(_ key: String, in strings: [String: Any]) -> [String: String] {
        let entry = strings[key] as? [String: Any]
        let locs = entry?["localizations"] as? [String: Any] ?? [:]
        var out: [String: String] = [:]
        for (lang, value) in locs {
            if let unit = (value as? [String: Any])?["stringUnit"] as? [String: Any],
               let text = unit["value"] as? String { out[lang] = text }
        }
        return out
    }

    func testButtonsAndRows_areSentenceCase_withEveryTranslation() {
        let strings = catalog
        for pair in renamed {
            XCTAssertNil(strings[pair.old], "\"\(pair.old)\" is still a key")
            XCTAssertNotNil(strings[pair.new], "\"\(pair.new)\" is missing")
            XCTAssertEqual(translations(pair.new, in: strings).count, 18, "\"\(pair.new)\" lost a translation")
        }
    }

    func testTheSyncLine_namesTheButtonAsItReads() {
        let strings = catalog
        XCTAssertNotNil(strings["Only syncs when you tap Sync now."])
        XCTAssertNil(strings["Only syncs when you tap Sync Now."])
    }

    func testTurkishAndBrazilianPortuguese_dropTheCopiedCapitals() {
        let strings = catalog
        let expected: [(key: String, lang: String, text: String)] = [
            ("Try again", "tr", "Tekrar dene"),
            ("Redeem code", "tr", "Kodu kullan"),
            ("Restore purchases", "tr", "Satın alımları geri yükle"),
            ("Sync now", "tr", "Şimdi eşitle"),
            ("Manage subscription", "tr", "Aboneliği yönet"),
            ("Delete series", "tr", "Seriyi sil"),
            ("Delete this occurrence", "tr", "Bu yinelemeyi sil"),
            ("Snooze duration", "tr", "Erteleme süresi"),
            ("Auto-delete (exc. notes)", "tr", "Otomatik sil (notlar hariç)"),
            ("Delete series", "pt-BR", "Excluir série"),
            ("Delete this occurrence", "pt-BR", "Excluir esta ocorrência"),
        ]
        for item in expected {
            XCTAssertEqual(translations(item.key, in: strings)[item.lang], item.text, "\(item.lang) \(item.key)")
        }
        // The Turkish sync line names the button by the button's own words.
        XCTAssertEqual(translations("Only syncs when you tap Sync now.", in: strings)["tr"],
                       "Yalnızca Şimdi eşitle'ye dokunduğunuzda senkronize edilir.")
    }
}
