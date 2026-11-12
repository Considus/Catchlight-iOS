//
//  RestoreBarHeightTests.swift
//  CatchlightTests (app module)
//
//  Phrase entry's Restore and Back buttons, on the bar above the keyboard, are half the Dailies
//  toolbar's height (owner 2026-11-11: "half height buttons generally"), 51.5pt, with the bar's
//  10pt above and 8pt below them, and split the width like the onboarding pair.
//

import XCTest
import UIKit
@testable import Catchlight

final class RestoreBarHeightTests: XCTestCase {

    func testRestoreAndBackAreHalfTheToolbarHeight() {
        let bar = RestoreKeyboardAccessory(onRestore: {}, onBack: {})
        bar.frame = CGRect(x: 0, y: 0, width: 402, height: bar.intrinsicContentSize.height)
        bar.layoutIfNeeded()
        let buttons = bar.subviews.compactMap { $0 as? UIButton }
        XCTAssertEqual(buttons.count, 2)
        for button in buttons {
            XCTAssertEqual(button.frame.height, 51.5, accuracy: 0.01, "\(button.currentTitle ?? "?") height")
            XCTAssertEqual(button.frame.minY, 10, accuracy: 0.01, "\(button.currentTitle ?? "?") top")
        }
        XCTAssertEqual(bar.intrinsicContentSize.height, 10 + 51.5 + 8, accuracy: 0.01)
    }

    /// The same size as the onboarding pair on "On this phone only" (owner 2026-11-12: "I prefer
    /// these for [the restore bar] in terms of size"): 17pt in from each side, 8pt apart, each
    /// half of what's left, so 180pt on a 402pt phone and 175.5pt on a 393pt one.
    func testRestoreAndBackSplitTheWidthLikeTheOnboardingPair() {
        for (width, each, backX) in [(CGFloat(402), CGFloat(180), CGFloat(205)), (393, 175.5, 200.5)] {
            let bar = RestoreKeyboardAccessory(onRestore: {}, onBack: {})
            bar.frame = CGRect(x: 0, y: 0, width: width, height: bar.intrinsicContentSize.height)
            bar.layoutIfNeeded()
            let buttons = bar.subviews.compactMap { $0 as? UIButton }.sorted { $0.frame.minX < $1.frame.minX }
            XCTAssertEqual(buttons.count, 2)
            guard buttons.count == 2 else { return }
            XCTAssertEqual(buttons[0].frame.minX, 17, accuracy: 0.01, "\(width): Restore leading inset")
            XCTAssertEqual(buttons[0].frame.width, each, accuracy: 0.01, "\(width): Restore width")
            XCTAssertEqual(buttons[1].frame.minX, backX, accuracy: 0.01, "\(width): Back leading edge")
            XCTAssertEqual(buttons[1].frame.width, each, accuracy: 0.01, "\(width): Back width")
            XCTAssertEqual(buttons[0].layer.cornerRadius, 14, accuracy: 0.01, "\(width): plain corners")
        }
    }

    /// Above Large text the two stack, full width, as the onboarding pairs do.
    func testRestoreAndBackStackAboveLargeText() {
        let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
        var bar: RestoreKeyboardAccessory!
        traits.performAsCurrent { bar = RestoreKeyboardAccessory(onRestore: {}, onBack: {}) }
        bar.traitOverrides.preferredContentSizeCategory = .accessibilityExtraLarge
        bar.updateTraitsIfNeeded()
        bar.frame = CGRect(x: 0, y: 0, width: 393, height: bar.intrinsicContentSize.height)
        bar.layoutIfNeeded()
        let buttons = bar.subviews.compactMap { $0 as? UIButton }.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(buttons.count, 2)
        guard buttons.count == 2 else { return }
        for b in buttons {
            XCTAssertEqual(b.frame.minX, 17, accuracy: 0.01)
            XCTAssertEqual(b.frame.width, 393 - 34, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(b.frame.height, 44)
        }
        XCTAssertEqual(buttons[1].frame.minY - buttons[0].frame.maxY, 8, accuracy: 0.01, "stack gap")
        XCTAssertEqual(bar.intrinsicContentSize.height, buttons[1].frame.maxY + 8, accuracy: 0.5, "bar fits the stack")
    }
}
