//
//  DailiesToolbarSizeTests.swift
//  CatchlightTests (app module)
//
//  The Dailies menu bar's labels and icons, one step bigger (owner 2026-11-12, "Step 1"):
//  label 13pt (was 11), icons 26pt with a 1.9 stroke (were 22 and 1.7), Add's square 40pt
//  (was 34). The bar's 103pt height and its columns don't change. Every label still fits its
//  column, in every language, at the largest text it grows to, on the small iPhone.
//

import XCTest
import UIKit
@testable import Catchlight

final class DailiesToolbarSizeTests: XCTestCase {

    func testSizesAreStepOne() {
        XCTAssertEqual(DailiesToolbarMetrics.labelSize, 13)
        XCTAssertEqual(DailiesToolbarMetrics.iconSize, 26)
        XCTAssertEqual(DailiesToolbarMetrics.iconStroke, 1.9)
        XCTAssertEqual(DailiesToolbarMetrics.addSquare, 40)
    }

    /// The label's font at its text-size cap (xxLarge), measured in each language against a
    /// quarter of the SE's bar (375 wide, less the two 17pt insets): nothing shrinks past the
    /// label's 0.8 floor, so nothing is cut off.
    func testEveryLabelFitsItsColumnOnTheSmallIPhoneInEveryLanguage() {
        let column: CGFloat = (375 - 34) / 4
        let traits = UITraitCollection(preferredContentSizeCategory: .extraExtraLarge)
        let points = CatchlightFont.scaledPoints(DailiesToolbarMetrics.labelSize, relativeTo: .caption2,
                                                 compatibleWith: traits)
        let font = UIFont.systemFont(ofSize: points, weight: .medium)
        let languages = ["en", "de", "fr", "es", "it", "pt-BR", "pt-PT", "nl", "pl", "sv", "da", "nb",
                         "fi", "tr", "ja", "ko", "th", "zh-Hans", "zh-Hant"]
        var measured = 0
        for language in languages {
            guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
                  let bundle = Bundle(path: path) else {
                XCTFail("\(language): no strings in the app"); continue
            }
            for key in ["Add", "Storyboard", "Sequence", "Search"] {
                let text = bundle.localizedString(forKey: key, value: key, table: nil)
                let width = (text as NSString).size(withAttributes: [.font: font]).width
                XCTAssertGreaterThanOrEqual(column / width, 0.8,
                                            "\(language) \(text): \(width)pt in a \(column)pt column")
                measured += 1
            }
        }
        XCTAssertEqual(measured, 76, "every label in every language was measured")
    }
}
