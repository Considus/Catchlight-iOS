//
//  TestSupport.swift
//  CatchlightCoreTests
//
//  Test-only doubles. NONE of these are production code.
//

import Foundation
import CryptoKit
@testable import CatchlightCore

enum TestFixtures {
    /// A deterministic synthetic 2048-word "wordlist" to exercise the BIP-39
    /// ALGORITHM (entropy ⇄ checksum ⇄ indices). NOT the official English wordlist;
    /// it only needs 2048 unique tokens.
    static func syntheticWordlist() -> BIP39Wordlist {
        let words = (0..<2048).map { "w\($0)" }
        return try! BIP39Wordlist(words: words)
    }

    /// A representative Take exercising every populated v1.0 field.
    static func richTake(id: UUID = UUID()) -> Take {
        Take(
            id: id,
            createdAt: ISO8601.date(from: "2026-05-01T09:00:00.000Z")!,
            modifiedAt: ISO8601.date(from: "2026-05-02T10:30:00.000Z")!,
            bodyText: "Buy film for the weekend shoot / café at 3",
            contentType: "plain",
            isNote: true,
            isTask: true,
            isComplete: false,
            isObie: false,
            timeReminder: TimeReminder(
                scheduledDate: ISO8601.date(from: "2026-05-03T15:00:00.000Z")!,
                isDelivered: false,
                notificationIdentifier: id.uuidString
            ),
            locationReminder: nil,
            checklistItems: [
                ChecklistItem(text: "Kodak Portra 400", isComplete: false),
                ChecklistItem(text: "Lens cloth", isComplete: true)
            ],
            attachments: [],
            sequenceIds: [],
            isSeeded: false
        )
    }
}
