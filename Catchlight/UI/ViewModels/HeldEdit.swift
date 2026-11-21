//
//  HeldEdit.swift
//  Catchlight
//
//  An edit whose save failed as the app locked, kept across the lock (owner, 2026-11-20:
//  "Hold it, give it back"). Sealed by Core's `TakeCrypto` under the Take's own item
//  key, as the store seals it, and held in memory only: nothing is written to disk, and nothing
//  is readable once the lock drops the keys. The unlock opens it and saves it again quietly, or
//  hands it back to the editor if that save fails too; then it is wiped. Quitting wipes it too.
//

import Foundation
import CatchlightCore

struct HeldEdit {
    let id: UUID
    private(set) var sealed: Data

    /// Throws when the Take can't be sealed; the caller says so after the unlock.
    init(sealing take: Take, keys: KeyHierarchy) throws {
        sealed = try TakeCrypto(keys: keys).seal(take)
        id = take.id
    }

    /// The Take as typed. Throws under keys that don't open it.
    func open(keys: KeyHierarchy) throws -> Take {
        try TakeCrypto(keys: keys).open(sealed, takeUUID: id)
    }

    /// Zeroes the sealed bytes.
    mutating func wipe() {
        sealed.resetBytes(in: 0..<sealed.count)
    }
}
