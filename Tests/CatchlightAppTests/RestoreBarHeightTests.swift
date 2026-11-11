//
//  RestoreBarHeightTests.swift
//  CatchlightTests (app module)
//
//  Phrase entry's Restore and Back buttons, on the bar above the keyboard, are half the Dailies
//  toolbar's height (owner 2026-11-11: "half height buttons generally"), 51.5pt, with the bar's
//  10pt above and 8pt below them.
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
}
