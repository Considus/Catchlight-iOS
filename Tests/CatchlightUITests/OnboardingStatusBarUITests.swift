//
//  OnboardingStatusBarUITests.swift
//  CatchlightUITests
//
//  Welcome and the closing screen sit on the Scene's colour field, which is dark in every Scene
//  in both appearances. The status bar there must draw light icons even in the light
//  appearance, and go back to the normal style on the steps that use the plain background.
//  Measured on a screenshot: the clock and battery are bright pixels on a dark field, or dark
//  pixels on a light one.
//

import XCTest

final class OnboardingStatusBarUITests: XCTestCase {

    private enum Icons { case light, dark }

    /// Reads the status bar's clock area of a screenshot against the background beside it:
    /// glyph pixels brighter than the background mean light icons, darker mean dark icons.
    private func icons(in app: XCUIApplication) -> Icons? {
        guard let image = XCUIScreen.main.screenshot().image.cgImage,
              let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let scale = CGFloat(image.width) / app.frame.width
        let bpp = image.bitsPerPixel / 8
        func luma(_ x: Int, _ y: Int) -> Double {
            let p = bytes + y * image.bytesPerRow + x * bpp
            return (0.299 * Double(p[0]) + 0.587 * Double(p[1]) + 0.114 * Double(p[2])) / 255
        }
        let background = luma(Int(200 * scale), Int(30 * scale))
        var brighter = 0, darker = 0
        for y in Int(14 * scale)..<Int(50 * scale) {
            for x in Int(24 * scale)..<Int(140 * scale) {
                let l = luma(x, y)
                if l > background + 0.25 { brighter += 1 } else if l < background - 0.25 { darker += 1 }
            }
        }
        if brighter >= 40 && darker < 40 { return .light }
        if darker >= 40 && brighter < 40 { return .dark }
        return nil
    }

    private func settle() { Thread.sleep(forTimeInterval: 1.0) }

    func testLightAppearance_fieldScreensDrawLightIcons_andOtherStepsDarkIcons() {
        continueAfterFailure = true
        var seen = [OnboardingStep]()
        walkOnboarding(appearance: "daylight") { step, app in
            settle()
            let expected: Icons? = switch step {
            case .welcome, .complete: .light
            case .restore, .storage, .basics: .dark
            default: nil
            }
            guard let expected else { return }
            XCTAssertEqual(icons(in: app), expected, "\(step): wrong status bar icons in the light appearance")
            seen.append(step)
        }
        XCTAssertEqual(seen.count, 5)
    }

    func testDarkAppearance_statusBarIconsAreLightEverywhere() {
        continueAfterFailure = true
        var seen = 0
        walkOnboarding(appearance: "night") { step, app in
            guard [.welcome, .storage, .complete].contains(step) else { return }
            settle()
            XCTAssertEqual(icons(in: app), .light, "\(step): wrong status bar icons in the dark appearance")
            seen += 1
        }
        XCTAssertEqual(seen, 3)
    }
}
