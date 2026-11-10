//
//  CardLayoutTests.swift
//  CatchlightTests (app module)
//
//  Covers the Take card's geometry now that the Iris sits inside the card's
//  top-left: where the text column starts, how short a card may be, and where
//  the card's leading edge falls for two common screen widths.
//

import XCTest
@testable import Catchlight

final class CardLayoutTests: XCTestCase {

    /// Iris inset 14 + Iris 44 + gap 12.
    func testTextColumnStartsClearOfTheIris() {
        XCTAssertEqual(CatchlightLayout.cardTextLeadingPad, 70)
    }

    /// Iris inset 14 above and below a 44pt Iris.
    func testCardMinimumHeightFitsTheIris() {
        XCTAssertEqual(CatchlightLayout.cardMinHeight, 72)
    }

    /// addColumnX(393) = 12 + (393 - 24) / 8 = 58.125, less 38.
    func testCardLeadingEdge_393() {
        let leading = CatchlightLayout.addColumnX(containerWidth: 393) - CatchlightLayout.cardLeadingOffset
        XCTAssertEqual(leading, 20.125, accuracy: 0.0001)
    }

    /// addColumnX(375) = 12 + (375 - 24) / 8 = 55.875, less 38.
    func testCardLeadingEdge_375() {
        let leading = CatchlightLayout.addColumnX(containerWidth: 375) - CatchlightLayout.cardLeadingOffset
        XCTAssertEqual(leading, 17.875, accuracy: 0.0001)
    }

    /// The default spacing setting stores 44; the old Iris's top half (22) no
    /// longer hangs into the gap, so the visible gap is 44 - 22 = 22.
    func testVisibleGap_defaultSetting_dropsTheOldIrisOverhang() {
        XCTAssertEqual(SettingsViewModel.TakeSpacing.default.gap, 44)
        XCTAssertEqual(CatchlightLayout.visibleCardGap(for: SettingsViewModel.TakeSpacing.default.gap), 22)
    }

    /// Compact stores 26; 26 - 22 = 4 is below the 10pt floor, so it shows 10.
    func testVisibleGap_neverBelowTheFloor() {
        XCTAssertEqual(CatchlightLayout.visibleCardGap(for: 26), 10)
        XCTAssertEqual(CatchlightLayout.visibleCardGap(for: 0), 10)
    }
}
