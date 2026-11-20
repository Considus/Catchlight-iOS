//
//  SentenceCaseLabelTests.swift
//  CatchlightTests (app module)
//
//  Labels and headings are in sentence case: "Appearance", not "APPEARANCE", and
//  "November 2026", not "NOVEMBER 2026". The month label starts with a capital in every
//  language, including the ones whose month names are lower case ("novembre 2026").
//  A source scan holds the rule: forcing capitals on text is allowed only at the lines
//  listed here, each with its reason.
//

import XCTest
@testable import Catchlight

final class SentenceCaseLabelTests: XCTestCase {

    // MARK: Month label

    func testMonthLabel_englishIsUnchanged() {
        XCTAssertEqual(TimelineMonthDivider.sentenceCase("November 2026", locale: Locale(identifier: "en_GB")),
                       "November 2026")
    }

    func testMonthLabel_lowerCaseMonth_getsACapital() {
        XCTAssertEqual(TimelineMonthDivider.sentenceCase("novembre 2026", locale: Locale(identifier: "fr_FR")),
                       "Novembre 2026")
        XCTAssertEqual(TimelineMonthDivider.sentenceCase("noviembre de 2026", locale: Locale(identifier: "es_ES")),
                       "Noviembre de 2026")
    }

    func testMonthLabel_capitalFollowsTheLanguage() {
        // Turkish dotted i: "i" becomes "İ", not "I".
        XCTAssertEqual(TimelineMonthDivider.sentenceCase("ilkbahar 2026", locale: Locale(identifier: "tr_TR")),
                       "İlkbahar 2026")
    }

    func testMonthLabel_onlyTheFirstLetterChanges() {
        XCTAssertEqual(TimelineMonthDivider.sentenceCase("listopad 2026", locale: Locale(identifier: "pl_PL")),
                       "Listopad 2026")
        XCTAssertEqual(TimelineMonthDivider.sentenceCase("", locale: Locale(identifier: "en_GB")), "")
    }

    // MARK: Source scan

    private struct Allowance {
        let file: String
        let line: String
        let count: Int
        let reason: String
    }

    private let allowances: [Allowance] = [
        .init(file: "Catchlight/UI/Views/PaywallView.swift", line: ".textCase(.uppercase)", count: 1,
              reason: "The paywall eyebrow: the brand sets eyebrow labels in capitals."),
        .init(file: "Catchlight/UI/Components/TakeStateWordStrip.swift",
              line: "static func capitals(_ word: String) -> String { word.localizedUppercase }", count: 1,
              reason: "OVERDUE and SNOOZED in the card strip, in capitals by the owner's choice (2026-11-12)."),
    ]

    private let capitalPatterns = [".textCase(.uppercase)", "uppercased()", "localizedUppercase"]

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .resolvingSymlinksInPath()
    }

    private func swiftSources() -> [(path: String, text: String)] {
        var found: [(String, String)] = []
        for dir in ["Catchlight", "CatchlightShare", "CatchlightWidgets"] {
            let base = repoRoot.appendingPathComponent(dir)
            guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let candidate as URL in walker where candidate.pathExtension == "swift" {
                let url = candidate.resolvingSymlinksInPath()
                guard !url.lastPathComponent.hasSuffix(".generated.swift") else { continue }
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    found.append((String(url.path.dropFirst(repoRoot.path.count + 1)), text))
                } catch {
                    XCTFail("could not read \(url.path): \(error)")
                }
            }
        }
        return found
    }

    /// The code part of each line, trimmed: comments are not code.
    private func codeLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").compactMap { raw in
            var line = raw
            if let slashes = line.range(of: "//") { line = String(line[..<slashes.lowerBound]) }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    func testSourceFinder_seesTheAppSources() {
        let sources = swiftSources()
        XCTAssertGreaterThan(sources.count, 50, "the scan found \(sources.count) files: the path is wrong")
        XCTAssertTrue(sources.contains { $0.path == "Catchlight/UI/Theme/SheetType.swift" })
        XCTAssertTrue(sources.contains { $0.path == "Catchlight/UI/Components/UIKitTimeline/UIKitTimeline.swift" })
    }

    func testNoLabel_isForcedIntoCapitals_withoutAReason() {
        var offenders: [String] = []
        for source in swiftSources() {
            for line in codeLines(source.text) where capitalPatterns.contains(where: line.contains) {
                let allowed = allowances.contains { $0.file == source.path && $0.line == line }
                if !allowed { offenders.append("\(source.path): \(line)") }
            }
        }
        XCTAssertEqual(offenders, [], "labels and headings are in sentence case; capitals need an allowance with a reason")
    }

    func testEveryAllowance_stillMatchesItsLine_exactlyAsOftenAsStated() {
        let sources = Dictionary(uniqueKeysWithValues: swiftSources().map { ($0.path, $0.text) })
        for allowance in allowances {
            let count = codeLines(sources[allowance.file] ?? "").filter { $0 == allowance.line }.count
            XCTAssertEqual(count, allowance.count, "\(allowance.file): \(allowance.line)")
        }
    }
}
