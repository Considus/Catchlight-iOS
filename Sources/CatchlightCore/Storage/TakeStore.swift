//
//  TakeStore.swift
//  CatchlightCore
//
//  The persistence abstraction. The portable core depends only on this protocol;
//  the iOS app provides the real `EncryptedTakeStore` (SQLite3 with per-item
//  AES-256-GCM sealed payload columns — see Catchlight/Database/
//  EncryptedTakeStore.swift). The in-memory implementation here mirrors the same
//  semantics so the sync engine, conflict resolver, and Obie/search rules can be
//  unit-tested without SQLite.
//
//  The store API deals in PLAINTEXT model values; the production implementation
//  seals each Take's content under its per-item key before it touches disk
//  (Encryption Architecture §8, revised 2026-06-10) and exposes only the id,
//  timestamps, and the Obie flag as queryable plaintext columns.
//
//  TOMBSTONES (2026-06-10): `delete(id:)` records a tombstone so the sync engine
//  can PROPAGATE deletions instead of inferring them from absence — inference
//  caused deleted Takes to be resurrected by the next pull, and transient blob
//  read failures to cascade into fleet-wide deletions.
//

import Foundation

/// A record that a Take was deleted locally and the deletion still needs to be
/// propagated to (or retained in) the cloud manifest.
public struct Tombstone: Codable, Equatable, Sendable {
    public let id: UUID
    public let deletedAt: Date

    public init(id: UUID, deletedAt: Date) {
        self.id = id
        self.deletedAt = ISO8601.truncateToMilliseconds(deletedAt)
    }
}

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

    // Sequences (saved searches — filter-based, 2026-06-10)
    func upsert(_ sequence: CatchlightSequence) throws
    func sequence(id: UUID) throws -> CatchlightSequence?
    func allSequences() throws -> [CatchlightSequence]
    /// Remove a saved Sequence (the filter definition only — never any Takes).
    /// Throws `StorageError.notFound` for an unknown id.
    func deleteSequence(id: UUID) throws

    // Obie — exactly one Obie across the whole store (UX §7).
    func currentObie() throws -> Take?
    func setObie(id: UUID, replaceExisting: Bool) throws

    // Sync bookkeeping
    func lastSyncDate() -> Date?
    func setLastSyncDate(_ date: Date)

    // Tombstones — deletion propagation (2026-06-10).
    /// All tombstones not yet purged. `delete(id:)` records one automatically.
    func tombstones() throws -> [Tombstone]
    /// Remove tombstones once the deletion is durably recorded in the uploaded
    /// cloud manifest (or applied from a remote tombstone).
    func purgeTombstones(ids: [UUID]) throws
}

/// In-memory `TakeStore` for tests and previews. Not used in production.
public final class InMemoryTakeStore: TakeStore {
    private var takes: [UUID: Take] = [:]
    private var sequences: [UUID: CatchlightSequence] = [:]
    private var lastSync: Date?
    private var tombstoneMap: [UUID: Tombstone] = [:]

    public init() {}

    public func upsert(_ take: Take) throws {
        // Single-Obie invariant under last-write-wins: an incoming Obie demotes
        // any existing one (mirrors EncryptedTakeStore so the two
        // implementations stay contract-identical for sync-applied rows).
        if take.isObie {
            for (id, var other) in takes where other.isObie && id != take.id {
                other.isObie = false
                takes[id] = other
            }
        }
        takes[take.id] = take
        // Re-creating an item supersedes any pending tombstone for it.
        tombstoneMap[take.id] = nil
    }

    public func delete(id: UUID) throws {
        guard takes[id] != nil else { throw StorageError.notFound(id) }
        takes[id] = nil
        tombstoneMap[id] = Tombstone(id: id, deletedAt: Date())
    }

    public func tombstones() throws -> [Tombstone] {
        tombstoneMap.values.sorted { $0.deletedAt < $1.deletedAt }
    }

    public func purgeTombstones(ids: [UUID]) throws {
        for id in ids { tombstoneMap[id] = nil }
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

    public func deleteSequence(id: UUID) throws {
        guard sequences[id] != nil else { throw StorageError.notFound(id) }
        sequences[id] = nil
    }
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
