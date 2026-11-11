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

    /// The cards sit at the toolbar's inset, 17pt from each side (owner 2026-11-11: "The Take card
    /// needs to exactly match the width of the menu bar").
    func testCardMargin_isTheToolbarsInset() {
        XCTAssertEqual(CatchlightLayout.cardMargin, CatchlightLayout.dockInset)
        XCTAssertEqual(CatchlightLayout.cardMargin, 17)
    }

    /// The Iris's left inset is worked out per width, (width − 34) / 8 − 22, so its centre lands
    /// exactly on `addColumnX`, under Add, on every phone (art director 2026-11-11, option a).
    func testIrisLeadingInset_perWidth() {
        let expected: [CGFloat: CGFloat] = [375: 20.625, 393: 22.875, 402: 24, 440: 28.75]
        for (width, inset) in expected {
            let add = CatchlightLayout.addColumnX(containerWidth: width)
            XCTAssertEqual(CatchlightLayout.irisLeadingInset(addColumnX: add), inset, accuracy: 0.0001, "width \(width)")
        }
    }

    /// Card edge + Iris inset + half the Iris = Add's centre, for every width.
    func testIrisCentre_sitsUnderAdd_onEveryWidth() {
        for width: CGFloat in [320, 375, 393, 402, 430, 440] {
            let add = CatchlightLayout.addColumnX(containerWidth: width)
            let centre = CatchlightLayout.cardMargin + CatchlightLayout.irisLeadingInset(addColumnX: add)
                + CatchlightLayout.circleDiameter / 2
            XCTAssertEqual(centre, add, accuracy: 0.0001, "width \(width)")
        }
    }

    /// The text column starts a fixed distance from the Iris: Iris inset + Iris 44 + gap 12.
    func testTextColumnStartsClearOfTheIris() {
        XCTAssertEqual(CatchlightLayout.cardTextLeadingPad(irisLeadingInset: 24), 80)
        XCTAssertEqual(CatchlightLayout.cardTextLeadingPad(irisLeadingInset: 20.625), 76.625, accuracy: 0.0001)
    }

    /// The top inset stays 14: 14 above and below a 44pt Iris.
    func testCardMinimumHeightFitsTheIris() {
        XCTAssertEqual(CatchlightLayout.irisInset, 14)
        XCTAssertEqual(CatchlightLayout.cardMinHeight, 72)
    }

    /// The date beside "Dailies" is 14pt with the wider cards (art director 2026-11-11).
    func testDailiesDate_is14() {
        XCTAssertEqual(DailiesHeading.dateSize, 14)
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
