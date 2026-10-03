//
//  TestSupport.swift
//  CatchlightAppTests
//
//  Test-only helpers. NONE of these are production code.
//
//  The two helpers the app-side suites need from the TestSupport.swift that moved
//  to the Catchlight-Core repo with the core tests. Core's copy is compiled into
//  its own test target only and is not exported, so these do not clash with it.
//
//  `TakeStoreContractTests.swift` beside this file is a verbatim copy of Core's
//  shared store contract for the same reason: `EncryptedTakeStoreContractTests`
//  subclasses it to run the contract against the production SQLite store. The
//  base class also runs its tests against `InMemoryTakeStore` here, as in Core.
//  Keep it identical to Core's copy at the pinned tag.
//

import Foundation
@testable import CatchlightCore

extension Take {
    /// Test sugar for the store and conflict suites, which only need to give a Take
    /// some body text and read it back. The production `primaryText` bridge was
    /// retired when the block editor landed (D-035 / Phase 2); this mirrors its old
    /// semantics (first prose block, inserted at the front if none).
    var primaryText: String {
        get {
            for block in blocks {
                if case .text(let textBlock) = block { return textBlock.text }
            }
            return ""
        }
        set {
            if let index = blocks.firstIndex(where: { if case .text = $0 { return true } else { return false } }) {
                if case .text(var textBlock) = blocks[index] {
                    textBlock.text = newValue
                    blocks[index] = .text(textBlock)
                }
            } else {
                blocks.insert(.text(TextBlock(text: newValue)), at: 0)
            }
        }
    }
}

enum TestFixtures {
    /// A representative Take exercising every populated v1.0 field. Interleaved
    /// block content: a prose line plus two check items (so it is a Task — D-034 —
    /// but incomplete, one item unticked).
    static func richTake(id: UUID = UUID()) -> Take {
        Take(
            id: id,
            createdAt: ISO8601.date(from: "2026-05-01T09:00:00.000Z")!,
            modifiedAt: ISO8601.date(from: "2026-05-02T10:30:00.000Z")!,
            blocks: [
                .textLine("Buy film for the weekend shoot / café at 3"),
                .checkItem("Kodak Portra 400", isComplete: false),
                .checkItem("Lens cloth", isComplete: true)
            ],
            contentType: "blocks/v2",
            isNote: true,
            isObie: false,
            timeReminder: TimeReminder(
                scheduledDate: ISO8601.date(from: "2026-05-03T15:00:00.000Z")!,
                isDelivered: false,
                notificationIdentifier: id.uuidString
            ),
            locationReminder: nil,
            attachments: [],
            isSeeded: false
        )
    }
}
