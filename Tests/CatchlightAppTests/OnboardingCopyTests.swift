//
//  OnboardingCopyTests.swift
//  CatchlightTests (app module)
//
//  The Iris point on the "A few things worth knowing" step names the Iris as a square in the
//  corner of the Take, because the Iris is now a square inside each card. The English source
//  is the new sentence, every catalog language carries a translation of it, and no catalog
//  holds the old sentence that called it a circle. The tests read the source file and the
//  catalog, so they hold the wording the step draws, not a copy of it.
//

import XCTest

final class OnboardingCopyTests: XCTestCase {

    private let newSentence = "Tap the square in the corner of any Take to make it a task, set a reminder, or make it important."
    private let oldSentence = "Tap the circle beside any Take to make it a task, set a reminder, or make it important."

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .resolvingSymlinksInPath()
    }

    private func catalog() throws -> [String: Any] {
        let url = repoRoot.appendingPathComponent("Catchlight/Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(json?["strings"] as? [String: Any])
    }

    private func languages(of entry: [String: Any]) -> Set<String> {
        Set((entry["localizations"] as? [String: Any] ?? [:]).keys)
    }

    func testTheIrisStepDrawsTheNewSentence() throws {
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Catchlight/UI/Views/OnboardingView.swift"),
                                encoding: .utf8)
        XCTAssertTrue(source.contains("String(localized: \"\(newSentence)\")"), "the Iris step does not draw the new sentence")
        XCTAssertFalse(source.contains(oldSentence), "the Iris step still draws the old sentence")
    }

    func testTheNewSentenceIsTranslatedIntoEveryLanguageTheCatalogCarries() throws {
        let strings = try catalog()
        let entry = try XCTUnwrap(strings[newSentence] as? [String: Any], "the catalog has no key for the new sentence")
        // English is the source language: a few keys spell out plural forms for it, but it is not a translation.
        let carried = Set(strings.values.compactMap { $0 as? [String: Any] }.flatMap { languages(of: $0) }).subtracting(["en"])
        XCTAssertGreaterThanOrEqual(carried.count, 18, "expected the catalog to carry 18 translations")
        let translated = languages(of: entry)
        XCTAssertEqual(carried.subtracting(translated), [], "languages with no translation of the new sentence")
        for (code, value) in entry["localizations"] as? [String: Any] ?? [:] {
            let unit = ((value as? [String: Any])?["stringUnit"] as? [String: Any])
            XCTAssertEqual(unit?["state"] as? String, "translated", "\(code) is not marked translated")
            XCTAssertFalse((unit?["value"] as? String ?? "").isEmpty, "\(code) is empty")
        }
    }

    func testNoCatalogStillCarriesTheOldCircleSentence() throws {
        XCTAssertNil(try catalog()[oldSentence], "the old sentence is still in the catalog")
    }
}
