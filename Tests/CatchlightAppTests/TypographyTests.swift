//
//  TypographyTests.swift
//  CatchlightTests (app module)
//
//  Headings and display text are Archivo, set expanded. Body text is the system
//  font. The old faces (Cormorant Garamond, DM Sans) are gone from the bundle and
//  from `UIAppFonts`. Times and counts draw tabular digits.
//

import XCTest
import SwiftUI
import UIKit
@testable import Catchlight

final class TypographyTests: XCTestCase {

    private let systemFamily = UIFont.systemFont(ofSize: 17).familyName

    // MARK: - Family

    func testHeadingFonts_resolveToArchivo() {
        let fonts: [(String, UIFont)] = [
            ("display scaled", CatchlightFont.uiDisplay(size: 28, relativeTo: .title2)),
            ("display fixed", CatchlightFont.uiDisplay(size: 28, relativeTo: nil)),
            ("page heading", CatchlightFont.uiDisplay(size: 24, relativeTo: .title3)),
            ("paywall hero", CatchlightFont.uiDisplay(size: 38, relativeTo: nil)),
        ]
        for (name, font) in fonts {
            XCTAssertEqual(font.familyName, "Archivo", "\(name) resolved to \(font.familyName)")
        }
    }

    func testBodyFonts_resolveToTheSystemFont() {
        let weights: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        for weight in weights {
            let font = CatchlightFont.uiBody(size: 14, weight: weight)
            XCTAssertEqual(font.familyName, systemFamily, "weight \(weight) resolved to \(font.familyName)")
        }
    }

    // MARK: - Width axis

    private func renderedWidth(of string: String, font: UIFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    func testWidthAxis_applies() {
        let normal = CatchlightFont.archivo(size: 28, weight: 500, width: 100)
        let wide = CatchlightFont.archivo(size: 28, weight: 500, width: 118)
        let sample = "Catchlight Dailies"
        XCTAssertGreaterThan(renderedWidth(of: sample, font: wide),
                             renderedWidth(of: sample, font: normal) * 1.05,
                             "wdth 118 should render clearly wider than wdth 100")
    }

    func testDisplayFont_isExpandedByDefault_andKeepsItWhenScaled() {
        let sample = "Catchlight Dailies"
        let normal = CatchlightFont.archivo(size: 28, weight: CatchlightFont.headingWeight, width: 100)
        let heading = CatchlightFont.uiDisplay(size: 28, relativeTo: nil)
        XCTAssertGreaterThan(renderedWidth(of: sample, font: heading), renderedWidth(of: sample, font: normal) * 1.05)
        let scaled = CatchlightFont.uiDisplay(size: 28, relativeTo: .title2)
        let scaledNormal = UIFontMetrics(forTextStyle: .title2).scaledFont(for: normal)
        XCTAssertGreaterThan(renderedWidth(of: sample, font: scaled), renderedWidth(of: sample, font: scaledNormal) * 1.05,
                             "Dynamic Type scaling must keep the width axis")
    }

    func testHeadingWeightAndWidth_areInsideTheSpecifiedRanges() {
        XCTAssertTrue((500...600).contains(CatchlightFont.headingWeight))
        XCTAssertTrue((112...125).contains(CatchlightFont.headingWidth))
    }

    // MARK: - Dynamic Type

    func testHeadingScalesWithDynamicType_likeTheStyleItIsRelativeTo() {
        let base = CatchlightFont.uiDisplay(size: 28, relativeTo: nil).pointSize
        let ax5 = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let expected = UIFontMetrics(forTextStyle: .title2).scaledValue(for: base, compatibleWith: ax5)
        let scaled = CatchlightFont.uiDisplay(size: 28, relativeTo: .title2, compatibleWith: ax5)
        XCTAssertEqual(scaled.pointSize, expected, accuracy: 0.5)
        XCTAssertGreaterThan(scaled.pointSize, base * 1.5)
    }

    func testBodyScalesWithDynamicType() {
        let ax5 = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let scaled = CatchlightFont.uiBody(size: 14, weight: .regular, relativeTo: .body, compatibleWith: ax5)
        XCTAssertGreaterThan(scaled.pointSize, 14 * 1.8)
    }

    // MARK: - Bundle

    func testNoBundledFontOrUIAppFontsEntryNamesTheOldFaces() throws {
        let bundle = Bundle(for: AppModel.self)
        let listed = (bundle.object(forInfoDictionaryKey: "UIAppFonts") as? [String]) ?? []
        XCTAssertFalse(listed.isEmpty, "UIAppFonts should list Archivo")
        for name in listed {
            XCTAssertFalse(name.localizedCaseInsensitiveContains("Cormorant"), name)
            XCTAssertFalse(name.localizedCaseInsensitiveContains("DMSans"), name)
        }
        let files = try FileManager.default.subpathsOfDirectory(atPath: bundle.bundlePath)
        for file in files where file.hasSuffix(".ttf") || file.hasSuffix(".otf") || file.hasPrefix("OFL") || file.contains("/OFL") {
            XCTAssertFalse(file.localizedCaseInsensitiveContains("Cormorant"), file)
            XCTAssertFalse(file.localizedCaseInsensitiveContains("DMSans"), file)
        }
    }

    func testArchivoIsRegistered() {
        let bundle = Bundle(for: AppModel.self)
        XCTAssertEqual((bundle.object(forInfoDictionaryKey: "UIAppFonts") as? [String]) ?? [], ["Archivo.ttf"])
        XCTAssertNotNil(UIFont(name: "Archivo-SemiBold", size: 12), "Archivo is not registered")
        XCTAssertNotNil(bundle.path(forResource: "OFL-Archivo", ofType: "txt"), "Archivo's licence is not bundled")
        XCTAssertNil(UIFont(name: "CormorantGaramond-Light", size: 12))
        XCTAssertNil(UIFont(name: "DMSans-9ptRegular", size: 12))
    }

    // MARK: - Tabular digits

    /// Width of `text` laid out as a SwiftUI `Text` in `font`.
    private func laidOutWidth(_ text: String, tabular: Bool) -> CGFloat {
        let base = CatchlightFont.ui(.medium, size: 11, relativeTo: .caption)
        let view = Group {
            if tabular { Text(text).font(base).monospacedDigit() } else { Text(text).font(base) }
        }.fixedSize()
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(in: CGSize(width: 1000, height: 1000)).width
    }

    func testTabularDigits_makeOnesAndZerosTheSameWidth() {
        XCTAssertNotEqual(laidOutWidth("1111", tabular: false), laidOutWidth("0000", tabular: false), accuracy: 0.01,
                          "the instrument cannot see a difference: proportional digits should differ")
        XCTAssertEqual(laidOutWidth("1111", tabular: true), laidOutWidth("0000", tabular: true), accuracy: 0.01)
    }
}
