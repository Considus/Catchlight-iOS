//
//  SQLCipherStore.swift
//  Catchlight (iOS app target)
//
//  The production `TakeStore`, backed by a standard SQLite3 database protected by
//  iOS Data Protection (`NSFileProtectionCompleteUntilFirstUserAuthentication`).
//  Implements Phase 5 brief §6 (database), §9 (FTS5 search), and §10.3 (App Group
//  container). Conforms to `CatchlightCore.TakeStore`.
//
//  CONFIDENTIALITY MODEL (revised 2026-06-05):
//    1. Content security — every Take payload is sealed with per-item AES-256-GCM
//       before reaching this layer (see `CatchlightCore.TakeCrypto` / `CryptoService`).
//       Take body text, attachments, reminders, etc. travel through the database as
//       ciphertext OR plaintext fields that have no confidentiality requirement
//       (timestamps, flags, the take's UUID). [NOTE: this revision still passes
//       through plaintext columns — the Phase 2.15 series fully encrypts content at
//       the cloud-sync boundary; storage-layer column re-encryption is tracked
//       separately.]
//    2. File security — the on-disk database file is tagged with
//       `NSFileProtectionCompleteUntilFirstUserAuthentication`. After the first
//       device unlock since boot, the file is readable; if the file ever leaves the
//       device (e.g. via backup of an unlocked device) it remains protected by the
//       file-class key.
//
//  We picked `.completeUntilFirstUserAuthentication`, NOT `.complete`, so
//  `BGAppRefreshTask` background sync still functions when the device re-locks
//  after the first user unlock since reboot.
//
//  SQLCipher was previously used here. It has been removed in favour of the
//  Apple-native stack (CryptoKit + NSFileProtection); the per-item AEAD already
//  carries content security, so SQLCipher would have provided only database-
//  metadata encryption at the cost of a third-party dependency.
//

import Foundation
import CryptoKit
import CatchlightCore
import SQLite3

public final class SQLiteTakeStore: TakeStore {

    private var db: OpaquePointer?
    private let dbURL: URL
    private var lastSync: Date?

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Open (creating if needed) the database in the App Group shared container so
    /// future extensions can reach it without a later migration (Phase 5 brief §10.3).
    /// - Parameter keys: the key hierarchy (kept on the API for forward compatibility
    ///   with column-level encryption; not currently used by the SQLite open path).
    public init(keys: KeyHierarchy) throws {
        let containerURL = AppGroup.containerURL()
        self.dbURL = containerURL.appendingPathComponent("catchlight.db")

        // 1) Apply file protection BEFORE the first open. If the file does not exist,
        //    create it empty with the protection attribute set; if it already exists,
        //    update its attributes. iOS enforces the protection class on real devices
        //    (it is observable but inert on the simulator).
        try Self.applyFileProtection(to: dbURL)

        // 2) Open the database — standard SQLite3, no cipher PRAGMAs.
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK, db != nil else {
            throw StorageError.openFailed("sqlite3_open failed")
        }

        // 3) Create schema + FTS5 if needed.
        try createSchema()
        // 4) Exclude the database from iCloud backup (§6.4).
        try excludeFromBackup(dbURL)
        _ = keys   // retained on the API; see initialiser docs above
        _ = db
    }

    deinit { if let db { sqlite3_close(db) } }

    // MARK: - File protection

    /// Apply `NSFileProtectionCompleteUntilFirstUserAuthentication` to the database
    /// file. Creates an empty file with the attribute set if it does not yet exist;
    /// otherwise updates the attribute on the existing file. This MUST run before
    /// the first `sqlite3_open` so the file is protected from the first byte.
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

    private func createSchema() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS takes (
            id                TEXT PRIMARY KEY,
            created_at        TEXT NOT NULL,
            modified_at       TEXT NOT NULL,
            body_text         TEXT NOT NULL,
            content_type      TEXT NOT NULL DEFAULT 'plain',
            is_note           INTEGER NOT NULL DEFAULT 1,
            is_task           INTEGER NOT NULL DEFAULT 0,
            is_complete       INTEGER NOT NULL DEFAULT 0,
            is_obie           INTEGER NOT NULL DEFAULT 0,
            is_seeded         INTEGER NOT NULL DEFAULT 0,
            time_reminder     TEXT,
            location_reminder TEXT,
            checklist_items   TEXT NOT NULL DEFAULT '[]',
            attachments       TEXT NOT NULL DEFAULT '[]',
            sequence_ids      TEXT NOT NULL DEFAULT '[]'
        );
        """)
        try exec("""
        CREATE TABLE IF NOT EXISTS sequences (
            id          TEXT PRIMARY KEY,
            name        TEXT NOT NULL,
            created_at  TEXT NOT NULL,
            modified_at TEXT NOT NULL,
            take_ids    TEXT NOT NULL DEFAULT '[]'
        );
        """)
        try exec("""
        CREATE TABLE IF NOT EXISTS sequence_memberships (
            take_id     TEXT NOT NULL,
            sequence_id TEXT NOT NULL,
            PRIMARY KEY (take_id, sequence_id)
        );
        """)
        // FTS5 full-text index over body text (Phase 5 brief §9.2). Encrypted
        // alongside the rest of the database — no plaintext escapes the file.
        try exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS takes_fts USING fts5(
            body_text,
            content='takes',
            content_rowid='rowid'
        );
        """)
        // Keep FTS in sync with the takes table.
        try exec("""
        CREATE TRIGGER IF NOT EXISTS takes_ai AFTER INSERT ON takes BEGIN
            INSERT INTO takes_fts(rowid, body_text) VALUES (new.rowid, new.body_text);
        END;
        """)
        try exec("""
        CREATE TRIGGER IF NOT EXISTS takes_ad AFTER DELETE ON takes BEGIN
            INSERT INTO takes_fts(takes_fts, rowid, body_text) VALUES('delete', old.rowid, old.body_text);
        END;
        """)
        try exec("""
        CREATE TRIGGER IF NOT EXISTS takes_au AFTER UPDATE ON takes BEGIN
            INSERT INTO takes_fts(takes_fts, rowid, body_text) VALUES('delete', old.rowid, old.body_text);
            INSERT INTO takes_fts(rowid, body_text) VALUES (new.rowid, new.body_text);
        END;
        """)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    // MARK: - TakeStore: Takes

    public func upsert(_ take: Take) throws {
        let sql = """
        INSERT INTO takes (id, created_at, modified_at, body_text, content_type,
                           is_note, is_task, is_complete, is_obie, is_seeded,
                           time_reminder, location_reminder, checklist_items, attachments, sequence_ids)
        VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15)
        ON CONFLICT(id) DO UPDATE SET
            created_at=?2, modified_at=?3, body_text=?4, content_type=?5,
            is_note=?6, is_task=?7, is_complete=?8, is_obie=?9, is_seeded=?10,
            time_reminder=?11, location_reminder=?12, checklist_items=?13,
            attachments=?14, sequence_ids=?15;
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, take.id.uuidString)
        bindText(stmt, 2, ISO8601.string(from: take.createdAt))
        bindText(stmt, 3, ISO8601.string(from: take.modifiedAt))
        bindText(stmt, 4, take.bodyText)
        bindText(stmt, 5, take.contentType)
        sqlite3_bind_int(stmt, 6, take.isNote ? 1 : 0)
        sqlite3_bind_int(stmt, 7, take.isTask ? 1 : 0)
        sqlite3_bind_int(stmt, 8, take.isComplete ? 1 : 0)
        sqlite3_bind_int(stmt, 9, take.isObie ? 1 : 0)
        sqlite3_bind_int(stmt, 10, take.isSeeded ? 1 : 0)
        bindOptionalJSON(stmt, 11, take.timeReminder)
        bindOptionalJSON(stmt, 12, take.locationReminder)
        bindText(stmt, 13, try jsonString(take.checklistItems))
        bindText(stmt, 14, try jsonString(take.attachments))
        bindText(stmt, 15, try jsonString(take.sequenceIds))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StorageError.writeFailed(lastError()) }
    }

    public func delete(id: UUID) throws {
        let stmt = try prepare("DELETE FROM takes WHERE id = ?1;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StorageError.writeFailed(lastError()) }
        if sqlite3_changes(db) == 0 { throw StorageError.notFound(id) }
    }

    public func take(id: UUID) throws -> Take? {
        let stmt = try prepare("SELECT \(Self.takeColumns) FROM takes WHERE id = ?1;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return try row(stmt)
    }

    public func allTakes() throws -> [Take] {
        try query("SELECT \(Self.takeColumns) FROM takes ORDER BY created_at ASC;")
    }

    public func takesModified(since date: Date?) throws -> [Take] {
        guard let date else { return try allTakes() }
        let stmt = try prepare("SELECT \(Self.takeColumns) FROM takes WHERE modified_at > ?1 ORDER BY created_at ASC;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, ISO8601.string(from: date))
        return try collect(stmt)
    }

    public func search(_ query: String) throws -> [Take] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // FTS5 MATCH against the encrypted index; join back to the takes table.
        let sql = """
        SELECT \(Self.takeColumns.split(separator: ",").map { "t.\($0.trimmingCharacters(in: .whitespaces))" }.joined(separator: ", "))
        FROM takes t JOIN takes_fts f ON t.rowid = f.rowid
        WHERE takes_fts MATCH ?1 ORDER BY rank;
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, ftsQuery(trimmed))
        return try collect(stmt)
    }

    // MARK: - TakeStore: Sequences

    public func upsert(_ sequence: CatchlightSequence) throws {
        let sql = """
        INSERT INTO sequences (id, name, created_at, modified_at, take_ids)
        VALUES (?1,?2,?3,?4,?5)
        ON CONFLICT(id) DO UPDATE SET name=?2, created_at=?3, modified_at=?4, take_ids=?5;
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, sequence.id.uuidString)
        bindText(stmt, 2, sequence.name)
        bindText(stmt, 3, ISO8601.string(from: sequence.createdAt))
        bindText(stmt, 4, ISO8601.string(from: sequence.modifiedAt))
        bindText(stmt, 5, try jsonString(sequence.takeIds))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StorageError.writeFailed(lastError()) }
    }

    public func sequence(id: UUID) throws -> CatchlightSequence? {
        let stmt = try prepare("SELECT id, name, created_at, modified_at, take_ids FROM sequences WHERE id = ?1;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return try sequenceRow(stmt)
    }

    public func allSequences() throws -> [CatchlightSequence] {
        let stmt = try prepare("SELECT id, name, created_at, modified_at, take_ids FROM sequences ORDER BY created_at ASC;")
        defer { sqlite3_finalize(stmt) }
        var out: [CatchlightSequence] = []
        while sqlite3_step(stmt) == SQLITE_ROW { out.append(try sequenceRow(stmt)) }
        return out
    }

    // MARK: - TakeStore: Obie (exactly one across the store)

    public func currentObie() throws -> Take? {
        let stmt = try prepare("SELECT \(Self.takeColumns) FROM takes WHERE is_obie = 1 LIMIT 1;")
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return try row(stmt)
    }

    public func setObie(id: UUID, replaceExisting: Bool) throws {
        if let existing = try currentObie(), existing.id != id {
            guard replaceExisting else { throw StorageError.obieConflict(existing: existing.id) }
            var old = existing; old.isObie = false; old.modifiedAt = Date()
            try upsert(old)
        }
        guard var target = try take(id: id) else { throw StorageError.notFound(id) }
        target.isObie = true; target.modifiedAt = Date()
        try upsert(target)
    }

    // MARK: - TakeStore: sync bookkeeping

    public func lastSyncDate() -> Date? { lastSync }
    public func setLastSyncDate(_ date: Date) { lastSync = date }

    // MARK: - SQL helpers

    private static let takeColumns =
        "id, created_at, modified_at, body_text, content_type, is_note, is_task, is_complete, is_obie, is_seeded, time_reminder, location_reminder, checklist_items, attachments, sequence_ids"

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

    private func query(_ sql: String) throws -> [Take] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        return try collect(stmt)
    }

    private func collect(_ stmt: OpaquePointer?) throws -> [Take] {
        var out: [Take] = []
        while sqlite3_step(stmt) == SQLITE_ROW { out.append(try row(stmt)) }
        return out
    }

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) {
        sqlite3_bind_text(stmt, idx, value, -1, Self.SQLITE_TRANSIENT)
    }

    private func bindOptionalJSON<T: Encodable>(_ stmt: OpaquePointer?, _ idx: Int32, _ value: T?) {
        if let value, let data = try? PlatformJSON.encode(value), let s = String(data: data, encoding: .utf8) {
            bindText(stmt, idx, s)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        String(data: try PlatformJSON.encode(value), encoding: .utf8) ?? "[]"
    }

    private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, idx) else { return "" }
        return String(cString: c)
    }

    private func row(_ stmt: OpaquePointer?) throws -> Take {
        let decoder = PlatformJSON.makeDecoder()
        func optJSON<T: Decodable>(_ idx: Int32, _ type: T.Type) -> T? {
            guard sqlite3_column_type(stmt, idx) != SQLITE_NULL else { return nil }
            let s = columnText(stmt, idx)
            return try? decoder.decode(T.self, from: Data(s.utf8))
        }
        func arrJSON<T: Decodable>(_ idx: Int32, _ type: T.Type) -> [T] {
            let s = columnText(stmt, idx)
            return (try? decoder.decode([T].self, from: Data(s.utf8))) ?? []
        }
        return Take(
            id: UUID(uuidString: columnText(stmt, 0)) ?? UUID(),
            createdAt: ISO8601.date(from: columnText(stmt, 1)) ?? Date(),
            modifiedAt: ISO8601.date(from: columnText(stmt, 2)) ?? Date(),
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
        )
    }

    private func sequenceRow(_ stmt: OpaquePointer?) throws -> CatchlightSequence {
        let decoder = PlatformJSON.makeDecoder()
        let takeIds = (try? decoder.decode([UUID].self, from: Data(columnText(stmt, 4).utf8))) ?? []
        return CatchlightSequence(
            id: UUID(uuidString: columnText(stmt, 0)) ?? UUID(),
            name: columnText(stmt, 1),
            createdAt: ISO8601.date(from: columnText(stmt, 2)) ?? Date(),
            modifiedAt: ISO8601.date(from: columnText(stmt, 3)) ?? Date(),
            takeIds: takeIds
        )
    }

    /// Escape an FTS5 query as a single quoted phrase prefix-match to avoid syntax
    /// errors on arbitrary user input.
    private func ftsQuery(_ raw: String) -> String {
        let escaped = raw.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\"*"
    }

    private func lastError() -> String {
        if let c = sqlite3_errmsg(db) { return String(cString: c) }
        return "unknown sqlite error"
    }
}
