//
//  FlatSurfaceSourceScanTests.swift
//  CatchlightTests (app module)
//
//  The redesign draws buttons, toggles, fields, cards and sheets flat, in rounded rectangles:
//  controls at `CatchlightLayout.controlRadius`, surfaces at `surfaceRadius`. No pills, no
//  circles for controls, no shadows, no raised gradients or materials, and every field
//  outlined with the `outline` token. This scans the app, share extension and widget sources.
//  A use that is not on the allow-list fails. Each allowance is pinned to the exact line of
//  code and to how many times that line appears in its file, with the reason it stays.
//

import XCTest

final class FlatSurfaceSourceScanTests: XCTestCase {

    /// One permitted use: the file, the exact line of code (trimmed), how many times it
    /// appears there, and why it stays.
    private struct Allowance {
        let file: String
        let line: String
        let count: Int
        let reason: String
    }

    private let fadeReason = "Scroll edge fade: one colour fading to clear under a heading or the dock. Not a raised surface."

    private lazy var allowances: [Allowance] = [
        .init(file: "Catchlight/UI/Views/DockPillRow.swift", line: "LinearGradient(stops: [", count: 1, reason: fadeReason),
        .init(file: "Catchlight/UI/Views/DailiesView.swift", line: "LinearGradient(", count: 1, reason: fadeReason),
        .init(file: "Catchlight/UI/Views/OnboardingView.swift",
              line: "LinearGradient(colors: [Color.ckBackground, Color.ckBackground.opacity(0)],", count: 1, reason: fadeReason),
        .init(file: "Catchlight/UI/Storyboard/StoryboardView.swift", line: "LinearGradient(", count: 1, reason: fadeReason),
        .init(file: "Catchlight/UI/Angles/ShotListView.swift", line: "LinearGradient(", count: 1, reason: fadeReason),
        .init(file: "CatchlightWidgets/WidgetSupport.swift", line: "RoundedRectangle(cornerRadius: radius, style: .continuous)", count: 2,
              reason: "Widget shapes are set by the widgets slice, sized to the widget's own corners."),
        .init(file: "CatchlightWidgets/WidgetSupport.swift", line: "let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)", count: 1,
              reason: "Widget shapes are set by the widgets slice, sized to the widget's own corners."),
        .init(file: "CatchlightWidgets/WidgetSupport.swift", line: "RoundedRectangle(cornerRadius: 1)", count: 1,
              reason: "The 2pt wide lit bar beside a widget's reminder line. A mark, not a control or surface."),
        .init(file: "Catchlight/UI/Components/PhraseKeyboardEntry.swift",
              line: "private let fade = CAGradientLayer()", count: 1, reason: fadeReason),
        .init(file: "Catchlight/UI/Settings/PrivacyPhraseView.swift", line: ".blur(radius: revealed ? 0 : 7)", count: 1,
              reason: "Privacy cover: hides the recovery phrase until it is revealed. Not a raised effect."),
        .init(file: "Catchlight/UI/Settings/SettingsView.swift", line: "Circle()", count: 2,
              reason: "The 8pt green or orange status dot beside Notifications. An indicator, not a control."),
        .init(file: "Catchlight/UI/Views/CatchlightWordmark.swift", line: "Circle()", count: 1,
              reason: "The lit dot of the wordmark's i. Brand mark, not a control."),
        .init(file: "Catchlight/UI/Theme/IrisGeometry.swift", line: "cornerRadius: 7.3 * s)", count: 1,
              reason: "The Iris draws its own shape, set by the Iris slice."),
        .init(file: "Catchlight/UI/Components/FocusRowView.swift", line: "let face = RoundedRectangle(cornerRadius: Self.markCornerRadius)", count: 1,
              reason: "The Focus row marks draw their own shape, set by the Focus row slice."),
        .init(file: "Catchlight/UI/Components/PhraseKeyboardEntry.swift", line: "let tf = UITextField()", count: 1,
              reason: "Its outline is the phrase grid cell's `flatField()`, which draws around the field in PhraseEntryGrid."),
    ]

    /// Constants a corner radius may be built from.
    private let radiusConstants = [
        "CatchlightLayout.controlRadius", "CatchlightLayout.surfaceRadius", "TakeCardStyle.cornerRadius",
        "FlatToggleMetrics.knobRadius", "FlatSegmentedMetrics.selectedRadius",
    ]

    private func matches(_ line: String, _ pattern: String) -> Bool {
        line.range(of: pattern, options: .regularExpression) != nil
    }

    /// What no source may contain unless allowed above. Each rule judges one line of code.
    private var rules: [(name: String, test: (String) -> Bool)] {
        [
            ("Capsule", { self.matches($0, "Capsule\\b") }),
            ("capsule button shape", { self.matches($0, "\\.capsule") }),
            ("circle shape", { self.matches($0, "\\bCircle\\(") || self.matches($0, "\\.clipShape\\(Circle") || self.matches($0, "\\bEllipse\\(") }),
            ("shadow", { self.matches($0, "\\.shadow\\(") }),
            ("layer shadow", { self.matches($0, "shadow(Opacity|Radius|Offset|Color)\\s*=") }),
            ("gradient", { self.matches($0, "(Linear|Radial|Angular|Elliptical)Gradient\\(") || $0.contains("CAGradientLayer") }),
            ("material", { self.matches($0, "\\.(ultraThin|thin|regular|thick|ultraThick)?Material\\b") }),
            ("blur", { self.matches($0, "\\.blur\\(") || self.matches($0, "UIBlurEffect|UIVisualEffectView") }),
            ("card shadow modifier", { $0.contains("daylightCardShadow") }),
            // Any corner radius not built from the radius constants: a number, `layer.cornerRadius =`,
            // `.cornerRadius(`, or a half-height pill.
            ("corner radius that is not a radius constant", {
                $0.contains("cornerRadius") && !self.radiusConstants.contains(where: $0.contains)
            }),
            ("half-height radius", {
                $0.localizedCaseInsensitiveContains("radius")
                    && self.matches($0, "(height|width|bounds|size|diameter|circle)\\w*\\s*/\\s*2")
            }),
        ]
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .resolvingSymlinksInPath()
    }

    private func swiftSources() -> [(path: String, text: String)] {
        var found: [(String, String)] = []
        for dir in ["Catchlight", "CatchlightShare", "CatchlightWidgets"] {
            let base = repoRoot.appendingPathComponent(dir)
            guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let candidate as URL in walker where candidate.pathExtension == "swift" {
                let url = candidate.resolvingSymlinksInPath()
                guard !url.lastPathComponent.hasSuffix(".generated.swift"),
                      let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                found.append((String(url.path.dropFirst(repoRoot.path.count + 1)), text))
            }
        }
        return found
    }

    /// The code part of each line, trimmed: comments are not code.
    private func codeLines(_ text: String) -> [(number: Int, line: String)] {
        text.components(separatedBy: "\n").enumerated().compactMap { index, raw in
            var line = raw
            if let slashes = line.range(of: "//") { line = String(line[..<slashes.lowerBound]) }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") { return nil }
            return (index + 1, trimmed)
        }
    }

    func testSourceFinder_seesTheAppSources() {
        let sources = swiftSources()
        XCTAssertGreaterThan(sources.count, 50, "the scan found \(sources.count) files: the path is wrong")
        XCTAssertTrue(sources.contains { $0.path == "Catchlight/UI/Views/DailiesToolbar.swift" })
        XCTAssertTrue(sources.contains { $0.path == "CatchlightShare/ShareSheetView.swift" })
        XCTAssertTrue(sources.contains { $0.path == "CatchlightWidgets/WidgetSupport.swift" })
    }

    func testNoSource_usesAPill_aCircle_aShadow_aRaisedGradientOrMaterial_withoutAReason() {
        var violations: [String] = []
        for (path, text) in swiftSources() {
            for (number, line) in codeLines(text) {
                for rule in rules where rule.test(line) {
                    let allowed = allowances.contains { $0.file == path && $0.line == line }
                    if !allowed { violations.append("\(path):\(number) \(rule.name): \(line)") }
                }
            }
        }
        XCTAssertTrue(violations.isEmpty, "\(violations.count) uses without a reason:\n" + violations.joined(separator: "\n"))
    }

    /// The allow-list must not rot: each entry's exact line still appears exactly `count` times.
    func testEveryAllowance_stillMatchesItsLine_exactlyAsOftenAsStated() {
        let sources = Dictionary(uniqueKeysWithValues: swiftSources().map { ($0.path, $0.text) })
        for allowance in allowances {
            let occurrences = codeLines(sources[allowance.file] ?? "").filter { $0.line == allowance.line }.count
            XCTAssertEqual(occurrences, allowance.count,
                           "\(allowance.file) has `\(allowance.line)` \(occurrences) times, not \(allowance.count): update the allowance (\(allowance.reason))")
        }
    }

    /// Every field draws the `outline` token. A SwiftUI field takes the next `flatField(` or
    /// `ckOutline` within 30 lines and before the next field, and each of those serves one field. A UIKit field needs its
    /// own `SceneToken.outline` in its file.
    func testEveryField_hasItsOwnOutlineFromTheOutlineToken() {
        let swiftUIField = "\\b(TextField|SecureField|TextEditor|PhraseTextField)\\("
        for (path, text) in swiftSources() {
            let lines = codeLines(text)
            var used = Set<Int>()
            let fields = lines.filter { matches($0.line, swiftUIField) && !$0.line.contains("struct ") }
            for (index, field) in fields.enumerated() {
                // The outline must come before the next field, so one field cannot borrow another's.
                let next = index + 1 < fields.count ? fields[index + 1].number : Int.max
                let marker = lines.first {
                    $0.number > field.number && $0.number <= field.number + 30 && $0.number < next
                        && !used.contains($0.number)
                        && ($0.line.contains("flatField(") || $0.line.contains("ckOutline"))
                }
                XCTAssertNotNil(marker, "\(path):\(field.number) is a field with no outline from the outline token within 30 lines: \(field.line)")
                if let marker { used.insert(marker.number) }
            }
            let uiKitFields = lines.filter { $0.line.contains("UITextField()") }
            let allowed = uiKitFields.filter { f in allowances.contains { $0.file == path && $0.line == f.line } }
            let outlines = lines.filter { $0.line.contains("SceneToken.outline") }.count
            XCTAssertGreaterThanOrEqual(outlines, uiKitFields.count - allowed.count,
                                        "\(path) has \(uiKitFields.count) UIKit fields but \(outlines) uses of the outline token")
        }
    }
}
