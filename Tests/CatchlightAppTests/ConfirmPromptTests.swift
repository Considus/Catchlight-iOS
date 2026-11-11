//
//  ConfirmPromptTests.swift
//  CatchlightTests (app module)
//
//  The Confirm step's prompt keeps to one line when it fits at 92 percent of its size, and wraps at
//  full size when it does not, so a long translation is never cut off. Laid out in the text width of a
//  393pt phone (345pt), at the default text size.
//

import XCTest
import SwiftUI
@testable import Catchlight

@MainActor
final class ConfirmPromptTests: XCTestCase {

    private func height(of text: String) -> CGFloat {
        let host = UIHostingController(rootView: ConfirmPrompt(text: text, keepsToOneLine: true)
            .environment(\.dynamicTypeSize, .large))
        return host.sizeThatFits(in: CGSize(width: 345, height: 1000)).height
    }

    private var oneLine: CGFloat { height(of: "Tap") }

    func testEnglishWithTwoTwoDigitPositions_staysOnOneLine() {
        let h = height(of: "Tap words 10, 11 and 12 from your phrase, in order.")
        XCTAssertEqual(h, oneLine, accuracy: 1, "the English prompt should keep to one line at 345pt")
    }

    func testLongTranslations_wrapInsteadOfBeingCutOff() {
        for text in ["Tippe der Reihe nach auf die Wörter 10, 11 und 12 deiner Phrase.",
                     "Stuknij słowa 10, 11 i 12 ze swojej frazy w odpowiedniej kolejności."] {
            XCTAssertGreaterThan(height(of: text), oneLine * 1.5, "'\(text)' is cut to one line instead of wrapping")
        }
    }
}
