//
//  FlatSurfaceSourceScanTests.swift
//  CatchlightTests (app module)
//
//  The redesign draws buttons, toggles, fields, cards and sheets flat, in rounded rectangles:
//  controls at `CatchlightLayout.controlRadius`, surfaces at `surfaceRadius`. No pills, no
//  shadows, no raised gradients or materials. This scans the app, share extension and widget
//  sources for each of those, with a short allow-list where one is justified, each with its
//  reason. A new use that is not on the list fails the test.
//

import XCTest

final class FlatSurfaceSourceScanTests: XCTestCase {

    /// One permitted use: the file it is in, the pattern, and why it stays.
    private struct Allowance {
        let file: String
        let pattern: String
        let reason: String
    }

    private let allowances: [Allowance] = [
        .init(file: "Catchlight/UI/Views/DockPillRow.swift", pattern: "LinearGradient",
              reason: "Scroll edge fade: the ground colour fading to clear under the dock. A single colour, not a raised surface."),
        .init(file: "Catchlight/UI/Views/DailiesView.swift", pattern: "LinearGradient",
              reason: "Scroll edge fade: the ground colour fading to clear under the heading."),
        .init(file: "Catchlight/UI/Views/OnboardingView.swift", pattern: "LinearGradient",
              reason: "Scroll edge fade: the ground colour fading to clear under the heading."),
        .init(file: "Catchlight/UI/Storyboard/StoryboardView.swift", pattern: "LinearGradient",
              reason: "Scroll edge fade: the ground colour fading to clear under the heading."),
        .init(file: "Catchlight/UI/Angles/ShotListView.swift", pattern: "LinearGradient",
              reason: "Scroll edge fade: the surface colour fading to clear under the heading."),
        .init(file: "Catchlight/UI/Components/KeyboardSearchBar.swift", pattern: "CAGradientLayer",
              reason: "Scroll edge fade above the keyboard bar: the ground colour fading to clear."),
        .init(file: "Catchlight/UI/Components/PhraseKeyboardEntry.swift", pattern: "CAGradientLayer",
              reason: "Scroll edge fade above the keyboard bar: the ground colour fading to clear."),
        .init(file: "Catchlight/UI/Settings/PrivacyPhraseView.swift", pattern: "\\.blur\\(",
              reason: "Privacy cover: hides the recovery phrase until it is revealed. Not a raised effect."),
        .init(file: "CatchlightWidgets/WidgetSupport.swift", pattern: "\\.shadow\\(",
              reason: "Widgets are redesigned in their own slice."),
        .init(file: "CatchlightWidgets/WidgetSupport.swift", pattern: "cornerRadius:\\s*\\d",
              reason: "Widgets are redesigned in their own slice."),
        .init(file: "Catchlight/UI/Components/IrisView.swift", pattern: "cornerRadius:\\s*\\d",
              reason: "The Iris draws its own shape, set by the Iris slice."),
    ]

    /// What no source may contain unless allowed above.
    private let forbidden: [(name: String, pattern: String)] = [
        ("Capsule", "Capsule\\b"),
        ("capsule button shape", "\\.capsule"),
        ("shadow", "\\.shadow\\("),
        ("layer shadow", "shadow(Opacity|Radius|Offset|Color)\\s*="),
        ("gradient", "(Linear|Radial|Angular|Elliptical)Gradient\\("),
        ("gradient layer", "CAGradientLayer"),
        ("material", "\\.(ultraThin|thin|regular|thick|ultraThick)?Material\\b|\\.bar\\b\\s*\\)"),
        ("blur", "\\.blur\\("),
        ("blur effect", "UIBlurEffect|UIVisualEffectView"),
        ("card shadow modifier", "daylightCardShadow"),
        ("literal corner radius", "cornerRadius:\\s*\\d"),
    ]

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
                let relative = String(url.path.dropFirst(repoRoot.path.count + 1))
                found.append((relative, text))
            }
        }
        return found
    }

    /// The code part of each line: comments are not code.
    private func codeLines(_ text: String) -> [(number: Int, line: String)] {
        text.components(separatedBy: "\n").enumerated().compactMap { index, raw in
            var line = raw
            if let slashes = line.range(of: "//") { line = String(line[..<slashes.lowerBound]) }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") { return nil }
            return (index + 1, line)
        }
    }

    func testSourceFinder_seesTheAppSources() {
        let sources = swiftSources()
        XCTAssertGreaterThan(sources.count, 50, "the scan found \(sources.count) files: the path is wrong")
        XCTAssertTrue(sources.contains { $0.path == "Catchlight/UI/Views/BottomDockView.swift" })
        XCTAssertTrue(sources.contains { $0.path == "CatchlightShare/ShareSheetView.swift" })
        XCTAssertTrue(sources.contains { $0.path == "CatchlightWidgets/WidgetSupport.swift" })
    }

    func testNoSource_usesAPill_aShadow_aRaisedGradientOrMaterial_withoutAReason() {
        var violations: [String] = []
        for (path, text) in swiftSources() {
            for (number, line) in codeLines(text) {
                for rule in forbidden {
                    guard line.range(of: rule.pattern, options: .regularExpression) != nil else { continue }
                    let allowed = allowances.contains {
                        $0.file == path && line.range(of: $0.pattern, options: .regularExpression) != nil
                    }
                    if !allowed { violations.append("\(path):\(number) \(rule.name): \(line.trimmingCharacters(in: .whitespaces))") }
                }
            }
        }
        XCTAssertTrue(violations.isEmpty, "\(violations.count) uses without a reason:\n" + violations.joined(separator: "\n"))
    }

    /// The allow-list must not rot: every entry still matches something in its file.
    func testEveryAllowance_stillMatchesAUse() {
        let sources = Dictionary(uniqueKeysWithValues: swiftSources().map { ($0.path, $0.text) })
        for allowance in allowances {
            let text = sources[allowance.file] ?? ""
            let hit = codeLines(text).contains { $0.line.range(of: allowance.pattern, options: .regularExpression) != nil }
            XCTAssertTrue(hit, "\(allowance.file) no longer has \(allowance.pattern): remove the allowance (\(allowance.reason))")
        }
    }

    /// The dock and the editor bar draw rounded squares, not circles.
    func testDockAndEditorBar_drawNoCircleButtons() {
        let sources = Dictionary(uniqueKeysWithValues: swiftSources().map { ($0.path, $0.text) })
        for file in ["Catchlight/UI/Views/BottomDockView.swift", "Catchlight/UI/Components/EditorKeyboardBar.swift"] {
            let circles = codeLines(sources[file] ?? "").filter { $0.line.contains("Circle(") }
            XCTAssertTrue(circles.isEmpty, "\(file) draws a circle: \(circles.map { "\($0.number)" })")
        }
    }

    /// Every field draws the `outline` token, never a tinted text colour.
    func testEveryFieldFile_drawsTheOutlineToken() {
        let sources = swiftSources()
        for (path, text) in sources where text.contains("TextField(") || text.contains("UITextField()") {
            XCTAssertTrue(text.contains("flatField(") || text.contains("SceneToken.outline"),
                          "\(path) has a field with no outline from the outline token")
        }
    }
}
