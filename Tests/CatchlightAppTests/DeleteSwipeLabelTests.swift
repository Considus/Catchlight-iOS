//
//  DeleteSwipeLabelTests.swift
//  CatchlightTests (app module)
//
//  The Delete swipe's label on the ruby fill. In Dark, white on ruby is below 4.5:1
//  (3.93:1 on #DB5252), so a Delete draws the Scene's on-accent colour instead, whether it
//  slides the row off (destructive) or asks first (a repeating reminder, or "confirm before
//  delete" on). In Light, white on ruby passes and stays.
//

import XCTest
import SwiftUI
@testable import Catchlight

final class DeleteSwipeLabelTests: XCTestCase {

    private func delete(asksFirst: Bool) -> SwipeAction {
        SwipeAction(title: "Delete", systemImage: "trash", tint: .ckRuby,
                    style: asksFirst ? .standard : .destructive, isDelete: true, perform: {})
    }

    private let done = SwipeAction(title: "Done", systemImage: "checkmark", tint: .ckEmber,
                                   contentColor: .ckOnAccent, style: .standard, perform: {})

    func testDeleteThatAsksFirst_dark_drawsOnAccent() {
        XCTAssertEqual(delete(asksFirst: true).labelInk(dark: true), .onAccent)
    }

    func testDeleteThatSlidesOff_dark_drawsOnAccent_unchanged() {
        XCTAssertEqual(delete(asksFirst: false).labelInk(dark: true), .onAccent)
    }

    func testDelete_light_keepsItsContentColour() {
        XCTAssertEqual(delete(asksFirst: true).labelInk(dark: false), .content)
        XCTAssertEqual(delete(asksFirst: false).labelInk(dark: false), .content)
    }

    func testOtherActions_keepTheirContentColour() {
        XCTAssertEqual(done.labelInk(dark: true), .content)
        XCTAssertEqual(done.labelInk(dark: false), .content)
    }
}
