//
//  TakeStore.swift
//  CatchlightCore
//
//  The persistence abstraction. The portable core depends only on this protocol;
//  the iOS app provides the real `SQLiteTakeStore` (AES-256-CBC encrypted SQLite
//  with the FTS5 search index — see Catchlight/Database/SQLCipherStore.swift). The
//  in-memory implementation here mirrors the same semantics so the sync engine,
//  conflict resolver, and Obie/search rules can be unit-tested without SQLCipher.
//
//  The store holds PLAINTEXT Takes. Confidentiality at rest is provided entirely
//  by SQLCipher encrypting the whole database file (Encryption Architecture §8) —
//  the store API itself deals in cleartext model values.
//

import Foundation

public protocol TakeStore: AnyObject {
    // Takes
    func upsert(_ take: Take) throws
    func delete(id: UUID) throws
    func take(id: UUID) throws -> Take?
    func allTakes() throws -> [Take]
    /// Takes whose `modifiedAt` is strictly after `date` (or all if nil). Used by
    /// outbound sync to find what changed.
    func takesModified(since date: Date?) throws -> [Take]
    /// Plain-text, local, full-text search across body text (FTS5 in the app target;
    /// case-insensitive substring here). Search scope per Phase 5 brief §9.
    func search(_ query: String) throws -> [Take]

    // Sequences
    func upsert(_ sequence: CatchlightSequence) throws
    func sequence(id: UUID) throws -> CatchlightSequence?
    func allSequences() throws -> [CatchlightSequence]

    // Obie — exactly one Obie across the whole store (UX §7).
    func currentObie() throws -> Take?
    func setObie(id: UUID, replaceExisting: Bool) throws

    // Sync bookkeeping
    func lastSyncDate() -> Date?
    func setLastSyncDate(_ date: Date)
}

/// In-memory `TakeStore` for tests and previews. Not used in production.
public final class InMemoryTakeStore: TakeStore {
    private var takes: [UUID: Take] = [:]
    private var sequences: [UUID: CatchlightSequence] = [:]
    private var lastSync: Date?

    public init() {}

    public func upsert(_ take: Take) throws { takes[take.id] = take }

    public func delete(id: UUID) throws {
        guard takes[id] != nil else { throw StorageError.notFound(id) }
        takes[id] = nil
    }

    public func take(id: UUID) throws -> Take? { takes[id] }

    public func allTakes() throws -> [Take] {
        takes.values.sorted { $0.createdAt < $1.createdAt }
    }

    public func takesModified(since date: Date?) throws -> [Take] {
        let all = try allTakes()
        guard let date else { return all }
        return all.filter { $0.modifiedAt > date }
    }

    public func search(_ query: String) throws -> [Take] {
        let q = query.lowercased()
        guard !q.isEmpty else { return [] }
        return try allTakes().filter { $0.bodyText.lowercased().contains(q) }
    }

    public func upsert(_ sequence: CatchlightSequence) throws { sequences[sequence.id] = sequence }
    public func sequence(id: UUID) throws -> CatchlightSequence? { sequences[id] }
    public func allSequences() throws -> [CatchlightSequence] {
        sequences.values.sorted { $0.createdAt < $1.createdAt }
    }

    public func currentObie() throws -> Take? { takes.values.first { $0.isObie } }

    public func setObie(id: UUID, replaceExisting: Bool) throws {
        guard var target = takes[id] else { throw StorageError.notFound(id) }
        if let existing = try currentObie(), existing.id != id {
            guard replaceExisting else { throw StorageError.obieConflict(existing: existing.id) }
            var old = existing
            old.isObie = false
            old.modifiedAt = Date()
            takes[old.id] = old
        }
        target.isObie = true
        target.modifiedAt = Date()
        takes[id] = target
    }

    public func lastSyncDate() -> Date? { lastSync }
    public func setLastSyncDate(_ date: Date) { lastSync = date }
}
