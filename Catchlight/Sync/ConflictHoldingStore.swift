//
//  ConflictHoldingStore.swift
//  Catchlight (iOS app target)
//
//  The store the app's own edits go through. It refuses every write to a Take that is
//  waiting in the conflict queue (owner 2026-10-07: "the file shouldn't update or edit until
//  the conflict is resolved"), so no screen, menu, swipe, reminder action or sweep can change
//  a held Take, whichever route it takes to the store. The UI refuses first and says why
//  (`AppModel.ensureEditable`); this is the backstop that holds when a route was missed.
//
//  Three things keep the RAW store and are never wrapped: the sync engine (it builds its own
//  store and is told which Takes are held), `ConflictQueue.resolve` (choosing a version is the
//  one write a held Take is waiting for), and seeding.
//

import Foundation
import CatchlightCore

/// The Takes waiting for the user's conflict choice. Shared by the queue that owns them, the
/// store that refuses writes to them and the sync coordinator that holds them back from the
/// cloud folder. Thread-safe: sync reads it off the main thread.
final class HeldTakes: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<UUID> = []
    private var generationValue = 0

    /// Changes whenever the queue is attached or detached (unlock, relock, a new account). A
    /// sync pass notes it as it starts, and its report is delivered into the queue only if it
    /// has not changed, so a pass begun for one session never lands in another.
    var generation: Int {
        lock.lock(); defer { lock.unlock() }
        return generationValue
    }

    /// The held ids and the generation, read together as a pass starts.
    var snapshot: (ids: Set<UUID>, generation: Int) {
        lock.lock(); defer { lock.unlock() }
        return (ids, generationValue)
    }

    /// Only the queue calls this.
    func newGeneration() {
        lock.lock(); generationValue += 1; lock.unlock()
    }

    var current: Set<UUID> {
        lock.lock(); defer { lock.unlock() }
        return ids
    }

    func contains(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return ids.contains(id)
    }

    /// Only the queue sets this.
    func replace(with new: Set<UUID>) {
        lock.lock(); ids = new; lock.unlock()
    }
}

/// A write the store refused because a Take is waiting for a conflict choice. `id` is the held
/// Take, which is not the one being written when the write would have demoted a held Obie.
struct TakeHeldForConflict: Error, Equatable {
    let id: UUID
}

final class ConflictHoldingStore: TakeStore {
    /// The unguarded store, for the conflict choice itself.
    let base: TakeStore
    private let held: HeldTakes

    init(base: TakeStore, held: HeldTakes) {
        self.base = base
        self.held = held
    }

    func isHeld(_ id: UUID) -> Bool { held.contains(id) }

    private func refuse(_ id: UUID) throws {
        if held.contains(id) { throw TakeHeldForConflict(id: id) }
    }

    /// An Obie written here demotes the current Obie inside the store, which is a write to
    /// that Take too.
    private func refuseDemotingHeldObie(besides id: UUID) throws {
        if let obie = try base.currentObie(), obie.id != id { try refuse(obie.id) }
    }

    // MARK: Writes — refused for a held Take

    func upsert(_ take: Take) throws {
        try refuse(take.id)
        if take.isObie { try refuseDemotingHeldObie(besides: take.id) }
        try base.upsert(take)
    }

    func delete(id: UUID) throws {
        try refuse(id)
        try base.delete(id: id)
    }

    func setObie(id: UUID, replaceExisting: Bool) throws {
        try refuse(id)
        try refuseDemotingHeldObie(besides: id)
        try base.setObie(id: id, replaceExisting: replaceExisting)
    }

    func applyRemote(_ take: Take) throws -> Bool {
        try refuse(take.id)
        return try base.applyRemote(take)
    }

    func release(id: UUID, ifNotModifiedAfter cutoff: Date) throws -> Bool {
        try refuse(id)
        return try base.release(id: id, ifNotModifiedAfter: cutoff)
    }

    // MARK: Everything else passes through

    func take(id: UUID) throws -> Take? { try base.take(id: id) }
    func allTakes() throws -> [Take] { try base.allTakes() }
    func takesModified(since date: Date?) throws -> [Take] { try base.takesModified(since: date) }
    func search(_ query: String) throws -> [Take] { try base.search(query) }
    func upsert(_ sequence: CatchlightSequence) throws { try base.upsert(sequence) }
    func sequence(id: UUID) throws -> CatchlightSequence? { try base.sequence(id: id) }
    func allSequences() throws -> [CatchlightSequence] { try base.allSequences() }
    func deleteSequence(id: UUID) throws { try base.deleteSequence(id: id) }
    func currentObie() throws -> Take? { try base.currentObie() }
    func lastSyncDate() -> Date? { base.lastSyncDate() }
    func setLastSyncDate(_ date: Date) { base.setLastSyncDate(date) }
    func tombstones() throws -> [Tombstone] { try base.tombstones() }
    func purgeTombstones(ids: [UUID]) throws { try base.purgeTombstones(ids: ids) }
}
