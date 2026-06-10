//
//  EncryptedTakeStore.swift
//  Catchlight (iOS app target)
//
//  The production `TakeStore`. SQLite3 with PER-ITEM AES-256-GCM SEALED PAYLOADS
//  (Encryption Architecture §8, revised 2026-06-10) plus iOS Data Protection on
//  the file. Replaces the former `SQLCipherStore.swift` / `SQLiteTakeStore`,
//  which stored body text, checklists, and reminders as plaintext columns and
//  mirrored them into a plaintext FTS5 index — contradicting both the in-code
//  comments and the documented threat model.
//
//  CONFIDENTIALITY MODEL (schema v2):
//    • Each Take row is: id, created_at, modified_at, is_obie, payload — where
//      `payload` is the FULL Take serialised via PlatformJSON and sealed with
//      `TakeCrypto` under the Take's per-item key (the same primitive the cloud
//      sync blobs use). Body text, activity flags, reminders (including any
//      future location data), checklists, and attachments NEVER touch disk in
//      plaintext.
//    • The only plaintext columns are the id (required for key derivation),
//      the two timestamps (needed for ordering and the sync watermark query),
//      and the single-bit Obie flag (needed for the uniqueness index). These
//      carry no content.
//    • Sequences are sealed the same way (payload column keyed by sequence id).
//    • FTS5 is GONE. Search decrypts and substring-matches in memory — the same
//      semantics as `InMemoryTakeStore`, so the two implementations are
//      contract-identical. At MVP scale (hundreds to a few thousand Takes,
//      ~µs per AES-GCM open) this is well within interactive budget.
//    • File security — the database directory carries
//      `NSFileProtectionCompleteUntilFirstUserAuthentication` so the db AND its
//      -wal/-shm sidecars inherit the class (sidecars previously got the App
//      Group default, which is weaker). `.completeUntilFirstUserAuthentication`
//      rather than `.complete` so BGAppRefreshTask sync still functions when
//      the device re-locks after first unlock since boot.
//
//  DURABILITY / INVARIANTS:
//    • `PRAGMA user_version = 2`; the legacy plaintext v1 schema is migrated
//      in-place (rows re-sealed, FTS dropped) inside a single transaction.
//    • Single-Obie is enforced by a partial UNIQUE index (which doubles as the
//      Obie lookup index); `setObie` runs in a transaction.
//    • `last_sync` and tombstones are PERSISTED (previously `lastSync` was an
//      in-memory var, so every relaunch reset the sync watermark).
//    • WAL journal + busy_timeout for safe App Group multi-process access.
//    • All public methods are serialised on an internal queue.
//    • Corrupt rows THROW `StorageError.corruptRow` — previously an unparseable
//      id silently became a fresh random UUID on every read, which would break
//      per-item key derivation and sync identity.
//

import Foundation
import CryptoKit
import CatchlightCore
import SQLite3

public final class EncryptedTakeStore: TakeStore {

    private var db: OpaquePointer?
    private let dbURL: URL
    private let crypto: TakeCrypto
    private let keys: KeyHierarchy
    private let queue = DispatchQueue(label: "com.considus.catchlight.store")

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let schemaVersion: Int32 = 2

    /// Open (creating if needed) the database.
    /// - Parameters:
    ///   - keys: the key hierarchy; per-item keys seal every payload column.
    ///   - directoryURL: where the database directory lives. Defaults to the App
    ///     Group container (so future extensions can reach it). Tests pass a
    ///     temp directory so they can never touch live user data.
    public init(keys: KeyHierarchy, directoryURL: URL? = nil) throws {
        self.keys = keys
        self.crypto = TakeCrypto(keys: keys)

        let baseDir = directoryURL ?? AppGroup.containerURL()
        let dbDir = baseDir.appendingPathComponent("Database", isDirectory: true)
        try Self.prepareProtectedDirectory(dbDir)
        self.dbURL = dbDir.appendingPathComponent("catchlight.db")

        // Migrate a legacy root-level database file into the protected directory.
        let legacyURL = baseDir.appendingPathComponent("catchlight.db")
        if FileManager.default.fileExists(atPath: legacyURL.path),
           !FileManager.default.fileExists(atPath: dbURL.path) {
            try? FileManager.default.moveItem(at: legacyURL, to: dbURL)
        }

        try Self.applyFileProtection(to: dbURL)

        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK, db != nil else {
            throw StorageError.openFailed("sqlite3_open failed")
        }
        // WAL + busy timeout: safe concurrent access from app + future extensions.
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA busy_timeout=5000;")
        try exec("PRAGMA foreign_keys=ON;")

        try migrateIfNeeded()
        try excludeFromBackup(dbURL)
        try Self.protectSidecars(of: dbURL)
    }

    deinit { if let db { sqlite3_close(db) } }

    // MARK: - File protection

    /// Create the database directory with the protection class set as the
    /// DIRECTORY default, so SQLite's -wal/-shm sidecars inherit it on creation.
    private static func prepareProtectedDirectory(_ url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        } else {
            try? fm.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        }
    }

    private static func applyFileProtection(to url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } else {
            let created = fm.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            if !created {
                throw StorageError.openFailed("could not create database file at \(url.path)")
            }
        }
    }

    /// Apply protection + backup exclusion to any -wal/-shm/journal sidecars
    /// that already exist (newly created ones inherit from the directory).
    private static func protectSidecars(of url: URL) throws {
        let fm = FileManager.default
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecar = URL(fileURLWithPath: url.path + suffix)
            guard fm.fileExists(atPath: sidecar.path) else { continue }
            try? fm.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: sidecar.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = sidecar
            try? mutableURL.setResourceValues(values)
        }
    }

    private func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    // MARK: - Schema / migration

    private func currentUserVersion() throws -> Int32 {
        let stmt = try prepare("PRAGMA user_version;")
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int(stmt, 0)
    }

    private func migrateIfNeeded() throws {
        let version = try currentUserVersion()
        switch version {
        case Self.schemaVersion:
            return
        case 0:
            try exec("BEGIN IMMEDIATE;")
            do {
                let legacyRows = try legacyPlaintextRowsIfAny()
                let legacySequences = try legacyPlaintextSequencesIfAny()
                try dropLegacySchemaIfAny()
                try createSchemaV2()
                for take in legacyRows { try insertOrReplace(take) }
                for sequence in legacySequences { try insertOrReplace(sequence) }
                try exec("PRAGMA user_version = \(Self.schemaVersion);")
                try exec("COMMIT;")
            } catch {
                try? exec("ROLLBACK;")
                throw error
            }
        default:
            // A FUTURE schema we don't understand. Refuse to touch it rather
            // than guessing (forward-compat guard).
            throw StorageError.openFailed("database schema v\(version) is newer than this app understands")
        }
    }

    private func createSchemaV2() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS takes (
            id          TEXT PRIMARY KEY,
            created_at  TEXT NOT NULL,
            modified_at TEXT NOT NULL,
            is_obie     INTEGER NOT NULL DEFAULT 0,
            payload     BLOB NOT NULL
        );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_takes_modified_at ON takes(modified_at);")
        try exec("CREATE INDEX IF NOT EXISTS idx_takes_created_at ON takes(created_at);")
        // Single-Obie invariant, enforced by the schema itself (and doubling as
        // the Obie lookup index).
        try exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_takes_single_obie ON takes(is_obie) WHERE is_obie = 1;")
        try exec("""
        CREATE TABLE IF NOT EXISTS sequences (
            id          TEXT PRIMARY KEY,
            created_at  TEXT NOT NULL,
            payload     BLOB NOT NULL
        );
        """)
        try exec("""
        CREATE TABLE IF NOT EXISTS tombstones (
            id         TEXT PRIMARY KEY,
            deleted_at TEXT NOT NULL
        );
        """)
        try exec("""
        CREATE TABLE IF NOT EXISTS sync_state (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)
    }

    /// Read every row of the legacy v1 plaintext schema, if present. Legacy
    /// corruption is surfaced (not papered over) — pre-release only developer
    /// devices carry v1 databases.
    private func legacyPlaintextRowsIfAny() throws -> [Take] {
        guard try tableExists("takes"), try columnExists("takes", "body_text") else { return [] }
        let stmt = try prepare("""
            SELECT id, created_at, modified_at, body_text, content_type, is_note, is_task,
                   is_complete, is_obie, is_seeded, time_reminder, location_reminder,
                   checklist_items, attachments, sequence_ids
            FROM takes;
            """)
        defer { sqlite3_finalize(stmt) }
        let decoder = PlatformJSON.makeDecoder()
        var out: [Take] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = UUID(uuidString: columnText(stmt, 0)),
                  let created = ISO8601.date(from: columnText(stmt, 1)),
                  let modified = ISO8601.date(from: columnText(stmt, 2)) else {
                throw StorageError.corruptRow("legacy take row has unparseable id/date")
            }
            func optJSON<T: Decodable>(_ idx: Int32, _ type: T.Type) -> T? {
                guard sqlite3_column_type(stmt, idx) != SQLITE_NULL else { return nil }
                return try? decoder.decode(T.self, from: Data(columnText(stmt, idx).utf8))
            }
            func arrJSON<T: Decodable>(_ idx: Int32, _ type: T.Type) -> [T] {
                (try? decoder.decode([T].self, from: Data(columnText(stmt, idx).utf8))) ?? []
            }
            out.append(Take(
                id: id,
                createdAt: created,
                modifiedAt: modified,
                bodyText: columnText(stmt, 3),
                contentType: columnText(stmt, 4),
                isNote: sqlite3_column_int(stmt, 5) == 1,
                isTask: sqlite3_column_int(stmt, 6) == 1,
                isComplete: sqlite3_column_int(stmt, 7) == 1,
                isObie: sqlite3_column_int(stmt, 8) == 1,
                timeReminder: optJSON(10, TimeReminder.self),
                locationReminder: optJSON(11, LocationTrigger.self),
                checklistItems: arrJSON(12, ChecklistItem.self),
                attachments: arrJSON(13, Attachment.self),
                sequenceIds: arrJSON(14, UUID.self),
                isSeeded: sqlite3_column_int(stmt, 9) == 1
            ))
        }
        return out
    }

    private func legacyPlaintextSequencesIfAny() throws -> [CatchlightSequence] {
        guard try tableExists("sequences"), try columnExists("sequences", "name") else { return [] }
        let stmt = try prepare("SELECT id, name, created_at, modified_at, take_ids FROM sequences;")
        defer { sqlite3_finalize(stmt) }
        let decoder = PlatformJSON.makeDecoder()
        var out: [CatchlightSequence] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = UUID(uuidString: columnText(stmt, 0)),
                  let created = ISO8601.date(from: columnText(stmt, 2)),
                  let modified = ISO8601.date(from: columnText(stmt, 3)) else {
                throw StorageError.corruptRow("legacy sequence row has unparseable id/date")
            }
            let takeIds = (try? decoder.decode([UUID].self, from: Data(columnText(stmt, 4).utf8))) ?? []
            out.append(CatchlightSequence(
                id: id,
                name: columnText(stmt, 1),
                createdAt: created,
                modifiedAt: modified,
                takeIds: takeIds
            ))
        }
        return out
    }

    private func dropLegacySchemaIfAny() throws {
        for table in ["takes_fts", "sequence_memberships", "takes", "sequences"] {
            try exec("DROP TABLE IF EXISTS \(table);")
        }
        for trigger in ["takes_ai", "takes_ad", "takes_au"] {
            try exec("DROP TRIGGER IF EXISTS \(trigger);")
        }
    }

    private func tableExists(_ name: String) throws -> Bool {
        let stmt = try prepare("SELECT 1 FROM sqlite_master WHERE type IN ('table','virtual table') AND name = ?1;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, name)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func columnExists(_ table: String, _ column: String) throws -> Bool {
        let stmt = try prepare("SELECT 1 FROM pragma_table_info(?1) WHERE name = ?2;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, table)
        bindText(stmt, 2, column)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    // MARK: - TakeStore: Takes

    public func upsert(_ take: Take) throws {
        try queue.sync {
            try exec("BEGIN IMMEDIATE;")
            var committed = false
            defer { if !committed { try? exec("ROLLBACK;") } }
            // Single-Obie invariant under last-write-wins: an incoming Obie
            // (e.g. applied from another device by sync) demotes any existing
            // one. Without this, the partial unique index rejected the row with
            // an opaque writeFailed and the whole upsert rolled back — and the
            // in-memory store (no index) silently accepted it, so the two
            // implementations diverged on the same input.
            if take.isObie {
                let demote = try prepare("UPDATE takes SET is_obie = 0 WHERE is_obie = 1 AND id != ?1;")
                defer { sqlite3_finalize(demote) }
                bindText(demote, 1, take.id.uuidString)
                guard sqlite3_step(demote) == SQLITE_DONE else { throw StorageError.writeFailed(lastError()) }
            }
            try insertOrReplace(take)
            // Re-creating an item supersedes any pending tombstone for it.
            let ts = try prepare("DELETE FROM tombstones WHERE id = ?1;")
            defer { sqlite3_finalize(ts) }
            bindText(ts, 1, take.id.uuidString)
            guard sqlite3_step(ts) == SQLITE_DONE else { throw StorageError.writeFailed(lastError()) }
            try exec("COMMIT;")
            committed = true
        }
    }

    /// Shared by upsert and migration. NOT serialised — callers hold the queue
    /// and the transaction.
    private func insertOrReplace(_ take: Take) throws {
        let sealed = try crypto.seal(take)
        let stmt = try prepare("""
            INSERT INTO takes (id, created_at, modified_at, is_obie, payload)
            VALUES (?1,?2,?3,?4,?5)
            ON CONFLICT(id) DO UPDATE SET
                created_at=?2, modified_at=?3, is_obie=?4, payload=?5;
            """)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, take.id.uuidString)
        bindText(stmt, 2, ISO8601.string(from: take.createdAt))
        bindText(stmt, 3, ISO8601.string(from: take.modifiedAt))
        sqlite3_bind_int(stmt, 4, take.isObie ? 1 : 0)
        bindBlob(stmt, 5, sealed)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StorageError.writeFailed(lastError()) }
    }

    public func delete(id: UUID) throws {
        try queue.sync {
            try exec("BEGIN IMMEDIATE;")
            var committed = false
            defer { if !committed { try? exec("ROLLBACK;") } }
            let stmt = try prepare("DELETE FROM takes WHERE id = ?1;")
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, id.uuidString)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw StorageError.writeFailed(lastError()) }
            guard sqlite3_changes(db) > 0 else { throw StorageError.notFound(id) }
            let ts = try prepare("INSERT OR REPLACE INTO tombstones (id, deleted_at) VALUES (?1, ?2);")
            defer { sqlite3_finalize(ts) }
            bindText(ts, 1, id.uuidString)
            bindText(ts, 2, ISO8601.string(from: Date()))
            guard sqlite3_step(ts) == SQLITE_DONE else { throw StorageError.writeFailed(lastError()) }
            try exec("COMMIT;")
            committed = true
        }
    }

    public func take(id: UUID) throws -> Take? {
        try queue.sync {
            let stmt = try prepare("SELECT id, payload FROM takes WHERE id = ?1;")
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, id.uuidString)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return try decodeTakeRow(stmt)
        }
    }

    public func allTakes() throws -> [Take] {
        try queue.sync {
            let stmt = try prepare("SELECT id, payload FROM takes ORDER BY created_at ASC;")
            defer { sqlite3_finalize(stmt) }
            return try collectTakes(stmt)
        }
    }

    public func takesModified(since date: Date?) throws -> [Take] {
        guard let date else { return try allTakes() }
        return try queue.sync {
            // Lexicographic comparison of the fixed-width UTC ISO strings is
            // chronologically correct; idx_takes_modified_at serves this query.
            let stmt = try prepare("SELECT id, payload FROM takes WHERE modified_at > ?1 ORDER BY created_at ASC;")
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, ISO8601.string(from: date))
            return try collectTakes(stmt)
        }
    }

    public func search(_ query: String) throws -> [Take] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        // Decrypt-side substring search (case-insensitive) — identical semantics
        // to InMemoryTakeStore. The plaintext FTS index this replaces leaked the
        // full body text of every Take to disk.
        return try allTakes().filter { $0.bodyText.lowercased().contains(q) }
    }

    // MARK: - TakeStore: Sequences

    public func upsert(_ sequence: CatchlightSequence) throws {
        try queue.sync { try insertOrReplace(sequence) }
    }

    /// Shared by upsert and migration. NOT serialised — callers hold the queue.
    private func insertOrReplace(_ sequence: CatchlightSequence) throws {
        let payload = try PlatformJSON.encode(sequence)
        let sealed = try CryptoService.encrypt(payload, key: keys.itemKey(takeUUID: sequence.id))
        let stmt = try prepare("""
            INSERT INTO sequences (id, created_at, payload) VALUES (?1,?2,?3)
            ON CONFLICT(id) DO UPDATE SET created_at=?2, payload=?3;
            """)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, sequence.id.uuidString)
        bindText(stmt, 2, ISO8601.string(from: sequence.createdAt))
        bindBlob(stmt, 3, sealed)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StorageError.writeFailed(lastError()) }
    }

    public func sequence(id: UUID) throws -> CatchlightSequence? {
        try queue.sync {
            let stmt = try prepare("SELECT id, payload FROM sequences WHERE id = ?1;")
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, id.uuidString)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return try decodeSequenceRow(stmt)
        }
    }

    public func allSequences() throws -> [CatchlightSequence] {
        try queue.sync {
            let stmt = try prepare("SELECT id, payload FROM sequences ORDER BY created_at ASC;")
            defer { sqlite3_finalize(stmt) }
            var out: [CatchlightSequence] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(try decodeSequenceRow(stmt)) }
            return out
        }
    }

    // MARK: - TakeStore: Obie (exactly one across the store)

    public func currentObie() throws -> Take? {
        try queue.sync {
            let stmt = try prepare("SELECT id, payload FROM takes WHERE is_obie = 1 LIMIT 1;")
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return try decodeTakeRow(stmt)
        }
    }

    public func setObie(id: UUID, replaceExisting: Bool) throws {
        try queue.sync {
            try exec("BEGIN IMMEDIATE;")
            var committed = false
            defer { if !committed { try? exec("ROLLBACK;") } }
            if let existing = try currentObieUnlocked(), existing.id != id {
                guard replaceExisting else {
                    throw StorageError.obieConflict(existing: existing.id)
                }
                var old = existing
                old.isObie = false
                old.modifiedAt = Date()
                try insertOrReplace(old)
            }
            guard let current = try takeUnlocked(id: id) else {
                throw StorageError.notFound(id)
            }
            var target = current
            target.isObie = true
            target.modifiedAt = Date()
            try insertOrReplace(target)
            try exec("COMMIT;")
            committed = true
        }
    }

    private func currentObieUnlocked() throws -> Take? {
        let stmt = try prepare("SELECT id, payload FROM takes WHERE is_obie = 1 LIMIT 1;")
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return try decodeTakeRow(stmt)
    }

    private func takeUnlocked(id: UUID) throws -> Take? {
        let stmt = try prepare("SELECT id, payload FROM takes WHERE id = ?1;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return try decodeTakeRow(stmt)
    }

    // MARK: - TakeStore: sync bookkeeping (persisted — survives relaunch)

    public func lastSyncDate() -> Date? {
        queue.sync {
            guard let stmt = try? prepare("SELECT value FROM sync_state WHERE key = 'last_sync';") else { return nil }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return ISO8601.date(from: columnText(stmt, 0))
        }
    }

    public func setLastSyncDate(_ date: Date) {
        queue.sync {
            guard let stmt = try? prepare("INSERT OR REPLACE INTO sync_state (key, value) VALUES ('last_sync', ?1);") else { return }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, ISO8601.string(from: date))
            _ = sqlite3_step(stmt)
        }
    }

    // MARK: - TakeStore: tombstones

    public func tombstones() throws -> [Tombstone] {
        try queue.sync {
            let stmt = try prepare("SELECT id, deleted_at FROM tombstones ORDER BY deleted_at ASC;")
            defer { sqlite3_finalize(stmt) }
            var out: [Tombstone] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let id = UUID(uuidString: columnText(stmt, 0)),
                      let deletedAt = ISO8601.date(from: columnText(stmt, 1)) else {
                    throw StorageError.corruptRow("tombstone row has unparseable id/date")
                }
                out.append(Tombstone(id: id, deletedAt: deletedAt))
            }
            return out
        }
    }

    public func purgeTombstones(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try queue.sync {
            let stmt = try prepare("DELETE FROM tombstones WHERE id = ?1;")
            defer { sqlite3_finalize(stmt) }
            for id in ids {
                sqlite3_reset(stmt)
                bindText(stmt, 1, id.uuidString)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw StorageError.writeFailed(lastError()) }
            }
        }
    }

    // MARK: - Row decoding (throws on corruption — never fabricates identity)

    private func decodeTakeRow(_ stmt: OpaquePointer?) throws -> Take {
        guard let id = UUID(uuidString: columnText(stmt, 0)) else {
            throw StorageError.corruptRow("take row has unparseable id")
        }
        let payload = columnBlob(stmt, 1)
        do {
            return try crypto.open(payload, takeUUID: id)
        } catch {
            throw StorageError.corruptRow("take \(id.uuidString) payload failed to open: \(error)")
        }
    }

    private func decodeSequenceRow(_ stmt: OpaquePointer?) throws -> CatchlightSequence {
        guard let id = UUID(uuidString: columnText(stmt, 0)) else {
            throw StorageError.corruptRow("sequence row has unparseable id")
        }
        let payload = columnBlob(stmt, 1)
        do {
            let plain = try CryptoService.decrypt(payload, key: keys.itemKey(takeUUID: id))
            return try PlatformJSON.decode(CatchlightSequence.self, from: plain)
        } catch {
            throw StorageError.corruptRow("sequence \(id.uuidString) payload failed to open: \(error)")
        }
    }

    // MARK: - SQL helpers

    private func exec(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw StorageError.writeFailed(lastError())
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.writeFailed(lastError())
        }
        return stmt
    }

    private func collectTakes(_ stmt: OpaquePointer?) throws -> [Take] {
        var out: [Take] = []
        while sqlite3_step(stmt) == SQLITE_ROW { out.append(try decodeTakeRow(stmt)) }
        return out
    }

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) {
        sqlite3_bind_text(stmt, idx, value, -1, Self.SQLITE_TRANSIENT)
    }

    private func bindBlob(_ stmt: OpaquePointer?, _ idx: Int32, _ value: Data) {
        value.withUnsafeBytes { raw in
            _ = sqlite3_bind_blob(stmt, idx, raw.baseAddress, Int32(raw.count), Self.SQLITE_TRANSIENT)
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, idx) else { return "" }
        return String(cString: c)
    }

    private func columnBlob(_ stmt: OpaquePointer?, _ idx: Int32) -> Data {
        guard let base = sqlite3_column_blob(stmt, idx) else { return Data() }
        let count = Int(sqlite3_column_bytes(stmt, idx))
        return Data(bytes: base, count: count)
    }

    private func lastError() -> String {
        if let c = sqlite3_errmsg(db) { return String(cString: c) }
        return "unknown sqlite error"
    }
}
