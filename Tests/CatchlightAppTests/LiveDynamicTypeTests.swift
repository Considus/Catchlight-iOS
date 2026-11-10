//
//  LiveDynamicTypeTests.swift
//  CatchlightTests (app module)
//
//  A screen left open while the text size changes must grow with it, without being
//  rebuilt. The size is changed on the hosting controller after it is on screen, the
//  way iOS delivers it, and the text is measured before and after.
//

import XCTest
import SwiftUI
@testable import Catchlight

@MainActor
final class LiveDynamicTypeTests: XCTestCase {

    /// Width of `view` hosted on screen, before and after the content size category
    /// is raised to `larger`.
    private func widths<V: View>(_ view: V, from start: UIContentSizeCategory = .large,
                                 to larger: UIContentSizeCategory = .accessibilityExtraExtraExtraLarge) -> (CGFloat, CGFloat) {
        let host = UIHostingController(rootView: view.fixedSize())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.traitOverrides.preferredContentSizeCategory = start
        host.view.layoutIfNeeded()
        let before = host.sizeThatFits(in: CGSize(width: 4000, height: 4000)).width
        host.traitOverrides.preferredContentSizeCategory = larger
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let after = host.sizeThatFits(in: CGSize(width: 4000, height: 4000)).width
        return (before, after)
    }

    func testSettingsLikeRows_growWhenTheTextSizeChanges() {
        let rows = VStack(alignment: .leading) {
            Text("Appearance mode").ckBody(.medium, size: 17, relativeTo: .body)
            Text("Newest first").ckBody(.regular, size: 15, relativeTo: .callout)
            Text("Created on 10/11/2026 at 14:39").ckBody(.regular, size: 11, relativeTo: .caption)
        }
        let (before, after) = widths(rows)
        XCTAssertGreaterThan(after, before * 1.8, "Settings-like rows did not grow: \(before) to \(after)")
    }

    func testDailiesLikeHeadingAndCard_growWhenTheTextSizeChanges() {
        let page = VStack {
            Text("DAILIES").ckDisplay(size: 24, relativeTo: .title3)
            Text("Call the framer back").ckBody(.regular, size: 14, relativeTo: .body)
        }
        let (before, after) = widths(page)
        XCTAssertGreaterThan(after, before * 1.5, "Dailies-like page did not grow: \(before) to \(after)")
    }

    func testFixedDisplayText_doesNotGrow() {
        let (before, after) = widths(Text("Welcome").ckDisplay(size: 28, relativeTo: nil))
        XCTAssertEqual(after, before, accuracy: 0.5)
    }
}
