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
    /// Build a SyncEngine with test defaults. `deviceId` is REQUIRED by the
    /// production initialiser (2026-06-10 remediation) — a fresh UUID default is
    /// fine for single-engine tests; multi-device tests pass explicit ids.
    static func engine(
        store: TakeStore,
        cloud: CloudFolder?,
        keys: KeyHierarchy,
        deviceId: UUID = UUID(),
        now: @escaping () -> Date = Date.init
    ) -> SyncEngine {
        SyncEngine(store: store, cloud: cloud, keys: keys, deviceId: deviceId, now: now)
    }

    /// A deterministic synthetic 2048-word "wordlist" to exercise the BIP-39
    /// ALGORITHM (entropy ⇄ checksum ⇄ indices). NOT the official English wordlist;
    /// it only needs 2048 unique tokens.
    static func syntheticWordlist() -> BIP39Wordlist {
        let words = (0..<2048).map { "w\($0)" }
        return try! BIP39Wordlist(words: words)
    }

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
