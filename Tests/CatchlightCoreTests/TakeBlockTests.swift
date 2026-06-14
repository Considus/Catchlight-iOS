//
//  TakeBlockTests.swift
//  CatchlightCoreTests — D-035
//
//  Codable + identity coverage for the block content model: `TextBlock`,
//  `TakeBlock` (the tagged-object wire format), and the interleaved round trip
//  through `[TakeBlock]`.
//

import XCTest
@testable import CatchlightCore

final class TakeBlockTests: XCTestCase {

    // MARK: - TextBlock

    func testTextBlock_roundTrip() throws {
        let block = TextBlock(text: "a line of prose")
        let decoded = try PlatformJSON.decode(TextBlock.self, from: try PlatformJSON.encode(block))
        XCTAssertEqual(decoded, block)
    }

    // MARK: - TakeBlock tagged-object format

    func testTakeBlock_text_encodesAsTaggedObject() throws {
        let id = UUID()
        let block = TakeBlock.text(TextBlock(id: id, text: "hello"))
        let json = String(data: try PlatformJSON.encode(block), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"kind\":\"text\""))
        XCTAssertTrue(json.contains("\"text\":\"hello\""))
        XCTAssertTrue(json.contains(id.uuidString))
        XCTAssertFalse(json.contains("isComplete"), "a text block carries no completion flag")
    }

    func testTakeBlock_check_encodesAsTaggedObject() throws {
        let block = TakeBlock.check(ChecklistItem(text: "milk", isComplete: true))
        let json = String(data: try PlatformJSON.encode(block), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"kind\":\"check\""))
        XCTAssertTrue(json.contains("\"text\":\"milk\""))
        XCTAssertTrue(json.contains("\"isComplete\":true"))
    }

    func testTakeBlock_roundTrip_preservesCaseAndId() throws {
        let cases: [TakeBlock] = [
            .text(TextBlock(text: "prose")),
            .check(ChecklistItem(text: "todo", isComplete: false)),
            .check(ChecklistItem(text: "done", isComplete: true))
        ]
        for block in cases {
            let decoded = try PlatformJSON.decode(TakeBlock.self, from: try PlatformJSON.encode(block))
            XCTAssertEqual(decoded, block)
            XCTAssertEqual(decoded.id, block.id, "block id is stable across a round trip")
        }
    }

    func testTakeBlock_id_reflectsPayload() {
        let textID = UUID()
        let checkID = UUID()
        XCTAssertEqual(TakeBlock.text(TextBlock(id: textID, text: "x")).id, textID)
        XCTAssertEqual(TakeBlock.check(ChecklistItem(id: checkID, text: "y")).id, checkID)
    }

    func testTakeBlock_check_toleratesMissingIsComplete() throws {
        // A partially-written payload (no isComplete) decodes as not-complete.
        let json = """
        {"kind":"check","id":"6B4D9E20-1A2B-4C3D-8E5F-001122334455","text":"x"}
        """
        let decoded = try PlatformJSON.decode(TakeBlock.self, from: Data(json.utf8))
        if case .check(let item) = decoded {
            XCTAssertFalse(item.isComplete)
            XCTAssertEqual(item.text, "x")
        } else {
            XCTFail("expected a check block")
        }
    }

    // MARK: - Interleaved array round trip

    func testInterleavedBlocks_roundTrip() throws {
        let blocks: [TakeBlock] = [
            .textLine("Shopping list"),
            .checkItem("apples"),
            .checkItem("bread", isComplete: true),
            .textLine("…and don't forget"),
            .checkItem("coffee")
        ]
        let decoded = try PlatformJSON.decode([TakeBlock].self, from: try PlatformJSON.encode(blocks))
        XCTAssertEqual(decoded, blocks, "interleaving and order survive serialisation")
    }
}
