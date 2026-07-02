//
//  LocalStoreReset.swift
//  Catchlight (iOS app target)
//
//  Destroys the local encrypted store on disk — the production primitive behind
//  two destructive flows:
//    • Settings → Second device (D-087): re-keying to another account leaves the
//      existing rows sealed under the OLD per-item keys, which the store's read
//      path THROWS on rather than hides. So the local Takes must be removed before
//      re-binding under the new key, or the timeline would break on undecryptable
//      rows. The user is warned first (Cancel/Continue) — this is that wipe.
//    • DebugReset (DEBUG only) — the on-device fresh-install reset delegates here.
//
//  Deleting the FILES (rather than issuing `delete` per Take through an unlocked
//  store) works even when the store can't be opened, and clears the SQLite WAL/SHM
//  sidecars and any sequences in one move. Mirrors EncryptedTakeStore's default
//  layout (`<app-group>/Database/catchlight.db`).
//

import Foundation
import CatchlightCore

enum LocalStoreReset {
    /// Remove the entire encrypted store directory (and any legacy root-level db)
    /// from the app-group container. Best-effort: a missing file is success.
    static func wipeDatabaseFiles() {
        let container = AppGroup.containerURL()
        let dbDir = container.appendingPathComponent("Database", isDirectory: true)
        try? FileManager.default.removeItem(at: dbDir)
        // Also remove a legacy root-level db file if one was ever migrated from.
        let legacy = container.appendingPathComponent("catchlight.db")
        try? FileManager.default.removeItem(at: legacy)
    }
}
