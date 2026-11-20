//
//  StorageChoiceVoiceOverUITests.swift
//  CatchlightUITests
//
//  On the onboarding step that asks where Takes live, VoiceOver reads each choice as one
//  button: its title, its description and, for Cloud, the iCloud Drive line. The words are
//  the ones on screen, never the code that holds them (a label built by dropping a localised
//  key into a string read out "LocalizedStringKey(key: …)").
//

import XCTest

final class StorageChoiceVoiceOverUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    func testStorageChoices_readTheirOwnWords_notCode() {
        let app = XCUIApplication()
        app.launchArguments = ["-appearanceMode", "night", "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        app.launch()

        let create = app.buttons["Create my Privacy phrase"]
        XCTAssertTrue(create.waitForExistence(timeout: 12), "onboarding did not appear")
        // The step's two choices are the only buttons under the hero; find them by position
        // in the step, not by their words, so a wrong label still fails on the comparison below.
        let choices = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Local' OR label BEGINSWITH 'Cloud'"))
        tapUntil(create, appears: choices.firstMatch)
        Thread.sleep(forTimeInterval: 0.6)
        let labels = choices.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(labels.count, 2, "expected the two storage choices, got \(labels)")
        guard labels.count == 2 else { return }
        let local = choices.element(boundBy: 0)
        let cloud = choices.element(boundBy: 1)

        XCTAssertEqual(local.label,
                       "Local: on this device only. Your Takes stay on this device and nowhere else. "
                       + "Your iPhone backup won't contain them, so if the phone goes, they go with it.")
        XCTAssertEqual(cloud.label,
                       "Cloud: backed up and restorable. Connect a cloud folder you control. Your Takes stay "
                       + "encrypted, we never see them, and your 12 words are what open them again on a new phone. "
                       + "Easiest to set up is iCloud Drive, it's built in.")
    }

    /// In German the label reads the German words, so it goes through the translations.
    func testStorageChoices_readTheTranslation() {
        let app = XCUIApplication()
        app.launchArguments = ["-appearanceMode", "night", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()

        let create = app.buttons["Meine Datenschutz-Phrase erstellen"]
        XCTAssertTrue(create.waitForExistence(timeout: 12), "onboarding did not appear in German")
        let local = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Lokal' OR label BEGINSWITH 'Local'")).firstMatch
        tapUntil(create, appears: local)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(local.label, "Lokal: nur auf diesem Gerät. Deine Takes bleiben auf diesem Gerät und nirgendwo sonst. Sie sind nicht in deinem iPhone-Backup enthalten. Geht dein Handy verloren, sind sie also ebenfalls weg.")
    }
}
