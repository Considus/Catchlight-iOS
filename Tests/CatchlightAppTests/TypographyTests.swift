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

@MainActor
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
        let view = Group {
            if tabular { Text(text).ckBody(.medium, size: 11, relativeTo: .caption).monospacedDigit() }
            else { Text(text).ckBody(.medium, size: 11, relativeTo: .caption) }
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

// MARK: - Non-Latin headings fall back to a sans

extension TypographyTests {

    /// The family of the font Core Text picks to draw `text` in `font`.
    func family(drawing text: String, in font: UIFont) -> String {
        let ns = text as NSString
        let used = CTFontCreateForString(font as CTFont, text as CFString, CFRange(location: 0, length: ns.length))
        return CTFontCopyFamilyName(used) as String
    }

    func testJapaneseHeading_fallsBackToHiraginoSans_notAMincho() {
        let font = CatchlightFont.uiDisplay(size: 28, relativeTo: nil, language: "ja")
        let family = family(drawing: "設定", in: font)
        XCTAssertFalse(family.localizedCaseInsensitiveContains("Mincho"), family)
        XCTAssertTrue(family.hasPrefix("Hiragino Sans"), family)
    }

    func testChineseHeadings_fallBackToPingFang() {
        for language in ["zh-Hans", "zh-Hant", "zh-HK"] {
            let font = CatchlightFont.uiDisplay(size: 28, relativeTo: nil, language: language)
            XCTAssertTrue(family(drawing: "設定", in: font).hasPrefix("PingFang"), language)
        }
    }

    func testKoreanHeading_fallsBackToAppleSDGothicNeo() {
        let font = CatchlightFont.uiDisplay(size: 28, relativeTo: nil, language: "ko")
        XCTAssertEqual(family(drawing: "설정", in: font), "Apple SD Gothic Neo")
    }

    func testLatinStaysArchivo_whateverTheLanguage() {
        for language in ["ja", "zh-Hans", "ko", "en", nil] {
            let font = CatchlightFont.uiDisplay(size: 28, relativeTo: nil, language: language)
            XCTAssertEqual(family(drawing: "Settings", in: font), "Archivo", language ?? "nil")
        }
    }

    func testTightLeading_isNegativeAndSmall() {
        let leading = CatchlightFont.tightLeading(size: 28)
        XCTAssertLessThan(leading, 0)
        XCTAssertGreaterThan(leading, -28 * 0.15, "tight, not overlapping")
    }
}

// MARK: - Caching, shared numbers, emphasis

@MainActor
extension TypographyTests {

    func testFontsAreBuiltOnce_notPerRender() {
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        _ = CatchlightFont.uiDisplay(size: 29, relativeTo: .title2, compatibleWith: traits, language: "ja")
        _ = CatchlightFont.uiBody(size: 13.5, weight: .medium, relativeTo: .callout, compatibleWith: traits)
        let built = CatchlightFont.cachedFontCount
        for _ in 0..<50 {
            _ = CatchlightFont.uiDisplay(size: 29, relativeTo: .title2, compatibleWith: traits, language: "ja")
            _ = CatchlightFont.uiBody(size: 13.5, weight: .medium, relativeTo: .callout, compatibleWith: traits)
        }
        XCTAssertEqual(CatchlightFont.cachedFontCount, built, "repeat calls built new fonts")
    }

    func testHeadingNumbersAreOneSharedSource() {
        XCTAssertEqual(CatchlightFont.headingWidth, HeadingAxes.width)
        XCTAssertEqual(CatchlightFont.headingWeight, HeadingAxes.weight)
        XCTAssertEqual(HeadingAxes.weightTag, 0x77676874)
        XCTAssertEqual(HeadingAxes.widthTag, 0x77647468)
    }

    func testHongKongChineseUsesPingFangHK() {
        XCTAssertEqual(CatchlightFont.displayFallback(for: "zh-Hant-HK"), "PingFangHK-Medium")
        XCTAssertEqual(CatchlightFont.displayFallback(for: "zh-Hant"), "PingFangTC-Medium")
        XCTAssertEqual(CatchlightFont.displayFallback(for: "zh-Hans"), "PingFangSC-Medium")
    }

    private func width(of view: some View) -> CGFloat {
        UIHostingController(rootView: view.fixedSize()).sizeThatFits(in: CGSize(width: 2000, height: 400)).width
    }

    /// The bold in "the **ONLY** key" is Markdown in the string. It must still draw bold
    /// in the system body font.
    func testMarkdownEmphasisStillDrawsBold() {
        let emphasised = width(of: EmphasisText("a **ONLY** b", .light, size: 16, relativeTo: .body))
        let flat = width(of: Text("a ONLY b").ckBody(.light, size: 16, relativeTo: .body))
        XCTAssertGreaterThan(emphasised, flat + 2, "the emphasised word did not get heavier: \(emphasised) against \(flat)")
        let none = width(of: EmphasisText("a ONLY b", .light, size: 16, relativeTo: .body))
        XCTAssertEqual(none, flat, accuracy: 0.5, "text without emphasis should match plain text")
    }

    // MARK: Multi-word headings

    private func catalogTitle(_ language: String) -> String {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return "SYNC CONFLICTS" }
        return bundle.localizedString(forKey: "SYNC CONFLICTS", value: "SYNC CONFLICTS", table: nil)
    }

    private func headingHeight(_ title: String, width: CGFloat, category: UIContentSizeCategory) -> CGFloat {
        let host = UIHostingController(rootView: PageHeading(verbatim: title))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 800))
        host.safeAreaRegions = []
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.traitOverrides.preferredContentSizeCategory = category
        host.view.layoutIfNeeded()
        return host.sizeThatFits(in: CGSize(width: width, height: 2000)).height
    }

    /// The scale the widest line needs to fit `width`: it must stay above the floor, so
    /// nothing is cut with an ellipsis.
    private func neededScale(_ title: String, width: CGFloat, category: UIContentSizeCategory) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let font = CatchlightFont.uiDisplay(size: 24, relativeTo: .title3, compatibleWith: traits)
        let lines = (PageHeading.twoLines(title) ?? title).components(separatedBy: "\n")
        let widest = lines.map { ($0 as NSString).size(withAttributes: [.font: font, .kern: CatchlightLayout.pageHeadingKerning]).width }.max() ?? 0
        // One line fits when it is no wider than the space. Otherwise it scales.
        return min(1, (width - CatchlightLayout.pageHeadingKerningComp) / widest)
    }

    func testMultiWordHeadings_wrapBetweenWords_neverInsideOne_andNeverTruncate() {
        let available: CGFloat = 402 - 2 * 56   // the Conflict header's width with the close-button slots
        for language in ["en", "it", "es", "fr"] {
            let title = catalogTitle(language)
            XCTAssertTrue(title.contains(" "), "\(language): \(title)")
            for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
                let height = headingHeight(title, width: available, category: category)
                let traits = UITraitCollection(preferredContentSizeCategory: category)
                let line = CatchlightFont.uiDisplay(size: 24, relativeTo: .title3, compatibleWith: traits).lineHeight
                XCTAssertLessThanOrEqual(height, line * 2.2, "\(language) \(category.rawValue): \(title) is \(height)pt tall, more than two lines")
                XCTAssertGreaterThan(neededScale(title, width: available, category: category), 0.3,
                                     "\(language) \(category.rawValue): \(title) would hit the scale floor and truncate")
            }
        }
    }

    func testSplit_isAtAWordBoundary_andBalanced() {
        XCTAssertEqual(PageHeading.twoLines("SHOT LIST"), "SHOT\nLIST")
        XCTAssertEqual(PageHeading.twoLines("SYNC CONFLICTS"), "SYNC\nCONFLICTS")
        XCTAssertEqual(PageHeading.twoLines("CONFLITTI DI SINCRONIZZAZIONE"), "CONFLITTI DI\nSINCRONIZZAZIONE")
        XCTAssertNil(PageHeading.twoLines("SETTINGS"))
    }
}
