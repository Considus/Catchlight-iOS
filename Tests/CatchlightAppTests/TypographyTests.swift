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

    /// Builds one display font and one body font the way a render does.
    private func renderFonts() -> (UIFont, UIFont) {
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        return (CatchlightFont.uiDisplay(size: 29, relativeTo: .title2, compatibleWith: traits, language: "ja"),
                CatchlightFont.uiBody(size: 13.5, weight: .medium, relativeTo: .callout, compatibleWith: traits))
    }

    func testFontsAreBuiltOnce_notPerRender() {
        let first = renderFonts()
        let built = CatchlightFont.fontBuildCount
        for _ in 0..<50 {
            let again = renderFonts()
            XCTAssertTrue(again.0 === first.0 && again.1 === first.1, "a repeat call returned a new font")
        }
        XCTAssertEqual(CatchlightFont.fontBuildCount, built, "repeat calls built fonts")
    }

    /// The control: with caching off the same calls do build, so the counter above can fail.
    func testBuildCounter_seesBuilds_whenCachingIsOff() {
        CatchlightFont.setCachingDisabledForTests(true)
        defer { CatchlightFont.setCachingDisabledForTests(false) }
        _ = renderFonts()
        let built = CatchlightFont.fontBuildCount
        for _ in 0..<5 { _ = renderFonts() }
        XCTAssertGreaterThan(CatchlightFont.fontBuildCount, built)
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

    /// View-level modifiers placed after `ckBody` still reach the text: the overdue time is
    /// italic (TakeRowView) and the filter label is kerned (UIKitTimeline).
    func testItalicAndKerning_stillApplyAfterCkBody() {
        let plain = width(of: Text("Overdue 12:40").ckBody(.medium, size: 11, relativeTo: .caption).monospacedDigit())
        let italic = width(of: Text("Overdue 12:40").ckBody(.medium, size: 11, relativeTo: .caption).monospacedDigit().italic(true))
        XCTAssertNotEqual(italic, plain, accuracy: 0.01, "italic did not change the text")
        let label = width(of: Text("SEQUENCE").ckBody(.regular, size: 14, relativeTo: .body))
        let kerned = width(of: Text("SEQUENCE").ckBody(.regular, size: 14, relativeTo: .body).kerning(0.5))
        XCTAssertEqual(kerned - label, 0.5 * 8, accuracy: 0.6, "kerning did not apply")
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
            }
        }
    }

    private static let catalogLanguages = ["en", "de", "fr", "es", "it", "pt-BR", "nl", "pt-PT", "pl", "sv", "da", "nb",
                                           "fi", "tr", "ja", "ko", "zh-Hans", "zh-Hant", "th"]
    private static let headingKeys = ["SETTINGS", "STORYBOARD", "SHOT LIST", "SYNC CONFLICTS", "DAILIES", "SEQUENCE", "SEARCH"]

    /// The headings whose single long word needs a soft hyphen at its compound join.
    private static let hyphenated: Set<String> = ["de|SYNC CONFLICTS", "nl|SYNC CONFLICTS", "da|SYNC CONFLICTS",
                                                  "nb|SYNC CONFLICTS", "fi|SYNC CONFLICTS"]

    func testLongCompoundHeadings_carryASoftHyphenAtTheJoin() {
        for entry in Self.hyphenated {
            let parts = entry.components(separatedBy: "|")
            let title = localized(parts[1], parts[0])
            XCTAssertEqual(title.components(separatedBy: PageHeading.softHyphen).count, 2, "\(entry): \(title)")
        }
        XCTAssertEqual(localized("SYNC CONFLICTS", "de"), "SYNCHRONISIERUNGS\u{00AD}KONFLIKTE")
    }

    private func localized(_ key: String, _ language: String) -> String {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// Every page heading in every catalog language, at the default size and AX5, in the
    /// narrowest header (the Conflicts header with its close-button slots). The drawn size
    /// is never below the body size at that Dynamic Type size, and no line breaks inside a
    /// word except at a soft hyphen.
    func testEveryHeadingInEveryLanguage_neverBelowBodySize_andNeverBreaksInsideAWord() {
        // The instrument must see a translation: German SYNC CONFLICTS differs from English.
        XCTAssertTrue(localized("SYNC CONFLICTS", "de").hasPrefix("SYNCHRONISIERUNGS"))
        let width: CGFloat = 402 - 2 * 56
        let available = width - CatchlightLayout.pageHeadingKerningComp - 1
        var report: [String] = []
        for language in Self.catalogLanguages {
            for key in Self.headingKeys {
                let title = localized(key, language)
                for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
                    let traits = UITraitCollection(preferredContentSizeCategory: category)
                    let body = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits).pointSize
                    let fit = PageHeading.fit(title, width: width, category: category, language: language)
                    let label = "\(language) \(key) \(category.rawValue == "UICTContentSizeCategoryL" ? "default" : "AX5")"
                    // The floor holds at the default size for every heading. At AX5 a word with
                    // no break point (STORYBOARD) can only shrink to fit, and a compound with
                    // a soft hyphen wraps at it and is larger than it could be on one line.
                    if category == .large {
                        XCTAssertGreaterThanOrEqual(fit.points, body - 0.01, "\(label): \(title) draws at \(fit.points), below body \(body)")
                    } else if Self.hyphenated.contains("\(language)|\(key)") {
                        let oneLine = PageHeading.fit(title.replacingOccurrences(of: PageHeading.softHyphen, with: ""),
                                                      width: width, category: category, language: language)
                        XCTAssertTrue(fit.wraps, "\(label): \(title) did not wrap at its hyphen")
                        XCTAssertGreaterThan(fit.points, oneLine.points * 1.3, "\(label): \(title) is no larger than on one line (\(fit.points) against \(oneLine.points))")
                    }
                    let font = CatchlightFont.uiDisplay(size: fit.points, relativeTo: nil, language: language)
                    func measure(_ s: String) -> CGFloat {
                        (s as NSString).size(withAttributes: [.font: font, .kern: CatchlightLayout.pageHeadingKerning]).width
                    }
                    let pieces = fit.text.components(separatedBy: "\n")
                    for piece in pieces {
                        XCTAssertLessThanOrEqual(measure(piece), available + 1, "\(label): \(piece) is cut or broken inside a word")
                    }
                    if fit.points < body * 1.5 { report.append("\(label) \(fit.points)pt wraps=\(fit.wraps)") }
                }
            }
        }
        print("HEADING REPORT\n" + report.joined(separator: "\n"))
    }

    /// The German heading at AX5 breaks at the soft hyphen onto more than one line.
    func testGermanSyncConflicts_atAX5_breaksAtTheHyphen() {
        let title = "SYNCHRONISIERUNGS\u{00AD}KONFLIKTE"
        let host = UIHostingController(rootView: PageHeading(verbatim: title))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 290, height: 900))
        host.safeAreaRegions = []
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        for _ in 0..<5 { host.view.layoutIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let height = host.view.systemLayoutSizeFitting(CGSize(width: 290, height: UIView.layoutFittingExpandedSize.height),
                                                       withHorizontalFittingPriority: .required,
                                                       verticalFittingPriority: .fittingSizeLevel).height
        let fit = PageHeading.fit(title, width: 290, category: .accessibilityExtraExtraExtraLarge, language: "de")
        let line = CatchlightFont.uiDisplay(size: fit.points, relativeTo: nil, language: "de").lineHeight
        XCTAssertGreaterThan(height, line * 1.6, "expected two lines of \(line), got \(height)pt")
        XCTAssertLessThan(height, line * 3.2, "expected two or three lines of \(line), got \(height)pt")
    }

    func testSplit_isAtAWordBoundary_andBalanced() {
        XCTAssertEqual(PageHeading.twoLines("SHOT LIST"), "SHOT\nLIST")
        XCTAssertEqual(PageHeading.twoLines("SYNC CONFLICTS"), "SYNC\nCONFLICTS")
        XCTAssertEqual(PageHeading.twoLines("CONFLITTI DI SINCRONIZZAZIONE"), "CONFLITTI DI\nSINCRONIZZAZIONE")
        XCTAssertNil(PageHeading.twoLines("SETTINGS"))
    }
}
