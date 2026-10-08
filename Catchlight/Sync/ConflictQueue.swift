//
//  ConflictQueue.swift
//  Catchlight (iOS app target) — Phase 6 UI, Task 6.15
//
//  The sync conflicts waiting for the user's choice, surfaced by `SyncEngine.pullInbound()`.
//  Populated by `BackgroundSyncCoordinator` after every sync; read by `DailiesView` (for the
//  banner) and `ConflictResolutionView` (for the picker).
//
//  A waiting Take is HELD until the user chooses (owner 2026-10-07: "the file shouldn't update
//  or edit until the conflict is resolved"). `held` names them: the app's edits refuse them
//  (`ConflictHoldingStore`, `AppModel.ensureEditable`) and every sync is told to leave them
//  alone (`SyncEngine.sync(holding:)`), so neither this phone's version nor the other device's
//  changes until the choice is made. "Skip for now" only hides a conflict until the next launch
//  or a newer version arrives; the Take stays held.
//
//  Kept on disk, sealed, so the hold survives a relaunch: one file per Take in the library's
//  `Database/Conflicts` folder, AES-256-GCM under Core's per-item key for the Take's id, with
//  the format named in the additional data so it can never be opened as anything else. The
//  same layout as the Mac app's queue. The folder sits inside the directory `LocalStoreReset`
//  removes, so Start over and Second device delete it with the library. Loaded at unlock (the
//  keys are needed), forgotten from memory at relock.
//
//  Unverified cloud copies stay in memory only and are not held: the engine never writes them
//  locally, and the next sync finds them again.
//

import Foundation
import Observation
import CryptoKit
import CatchlightCore

@Observable
@MainActor
final class ConflictQueue {

    /// Names the file format in each file's additional data.
    nonisolated static let format = Data("catchlight.ios.conflict.v1".utf8)

    /// Where the queue is kept: inside the library directory `LocalStoreReset` removes.
    nonisolated static var defaultDirectory: URL {
        LocalStoreReset.databaseDirectory.appendingPathComponent("Conflicts", isDirectory: true)
    }

    /// Every conflict waiting for a choice, skipped or not, oldest first.
    private var waiting: [(local: Take, remote: Take)] = []

    /// Hidden by "Skip for now" until the next launch or a newer version. Still held.
    private var skipped: Set<UUID> = []

    /// The conflicts to show, in the order they were surfaced (oldest first). Each pair is the
    /// shape `SyncEngine.pullInbound()` reports.
    var pending: [(local: Take, remote: Take)] {
        waiting.filter { !skipped.contains($0.local.id) }
    }

    /// The Takes waiting for a choice, skipped ones included. Shared with the store that
    /// refuses writes to them and the sync that holds them back.
    let held = HeldTakes()

    func isHeld(_ id: UUID) -> Bool { held.contains(id) }

    /// Takes whose conflict file is on disk but did not open with these keys. Held all the
    /// same, read-only, because the file may be the only copy of the other version; there is
    /// no pair to show, so they can't be resolved here.
    private(set) var unreadable: Set<UUID> = []

    @ObservationIgnored private var directory: URL?
    @ObservationIgnored private var keys: KeyHierarchy?

    /// False between `detach()` and the next `attach`: locked, or the account is being
    /// replaced or erased. A sync pass that finishes then delivers nothing into the queue
    /// (the coordinator also drops a delivery from an older generation, `HeldTakes`).
    /// A new queue starts accepting, in memory only, for previews and UI tests.
    @ObservationIgnored private var accepting = true

    private func waitingChanged() {
        held.replace(with: Set(waiting.map(\.local.id)).union(unreadable))
    }

    // MARK: - Lifetime

    /// Load the queue kept on disk, once the keys are in hand (unlock, onboarding, a second
    /// device's re-key). Replaces whatever is in memory, which belonged to a locked session or
    /// another account.
    func attach(keys: KeyHierarchy, directory: URL = ConflictQueue.defaultDirectory) {
        self.directory = directory
        self.keys = keys
        accepting = true
        held.newGeneration()
        skipped.removeAll()
        unverified.removeAll()
        unreadable.removeAll()
        var loaded: [(pair: (local: Take, remote: Take), date: Date)] = []
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for url in files where url.pathExtension == "conflict" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            do {
                let pair = try Self.open(Data(contentsOf: url), id: id, keys: keys)
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                loaded.append((pair, date))
            } catch {
                // Kept as it is, never deleted: it may hold the only copy of the other version.
                // And its Take stays held, so the owner's rule holds even here.
                unreadable.insert(id)
            }
        }
        waiting = loaded.sorted { $0.date < $1.date }.map(\.pair)
        waitingChanged()
        // `AppModel` shows `.conflictsUnreadable` on the strip when `unreadable` isn't empty.
    }

    /// Forget the queue from memory at relock: it holds decrypted Takes. The files stay, and
    /// the next unlock loads them again.
    /// Also at Start over and Second device, before the library goes, so nothing a late sync
    /// delivers can write a file sealed under the old keys.
    func detach() {
        directory = nil
        keys = nil
        accepting = false
        held.newGeneration()
        waiting.removeAll()
        skipped.removeAll()
        unverified.removeAll()
        unreadable.removeAll()
        waitingChanged()
    }

    /// Let go of conflicts whose Take has left this device: another device made it a Script,
    /// and the sync released it (or kept this device's edit as a new Take and released the
    /// original — `SyncReport.forkedFromScripts`). Nothing is left to choose between: the
    /// other version is that device's Script, and this device's version, if edited, is the new
    /// Take. The pair, its file and its hold go.
    func release(_ ids: [UUID]) {
        guard accepting else { return }
        let gone = Set(ids).intersection(waiting.map(\.local.id))
        guard !gone.isEmpty else { return }
        waiting.removeAll { gone.contains($0.local.id) }
        skipped.subtract(gone)
        waitingChanged()
        for id in gone { removeFile(id) }
    }

    // MARK: - Conflicts

    /// Add new conflicts. Dedup is by Take id, but an INCOMING pair REPLACES a pending pair for
    /// the same id (2026-06-10): if either side changed between syncs, the user must resolve
    /// against the newest snapshot. A newer pair also shows a skipped conflict again.
    /// Safe to call repeatedly with the same SyncReport (idempotent).
    func enqueue(_ conflicts: [(local: Take, remote: Take)]) {
        guard accepting else { return }
        var added = 0
        for pair in conflicts {
            let id = pair.local.id
            if let idx = waiting.firstIndex(where: { $0.local.id == id }) {
                if waiting[idx].local != pair.local || waiting[idx].remote != pair.remote {
                    skipped.remove(id)
                }
                waiting[idx] = pair
            } else {
                waiting.append(pair)
                added += 1
            }
            persist(pair)
        }
        waitingChanged()
        // Record newly-surfaced conflicts to the content-free diagnostics log (D-085) — a
        // count only, no Take content (the banner shows the same count).
        if added > 0 {
            // Shown in Notice History, so recorded in the device language.
            DiagnosticsLog.shared.record(.conflictsChanged(added))
        }
    }

    /// Resolve a single conflict by writing the chosen winner to the store and releasing the
    /// hold. No-op if the id is no longer waiting (e.g. the user resolved it on another row
    /// first). `store` is the RAW store: this is the one write a held Take is waiting for.
    func resolve(id: UUID, keepLocal: Bool, store: TakeStore) throws {
        guard let idx = waiting.firstIndex(where: { $0.local.id == id }) else { return }
        let pair = waiting[idx]
        // This phone's version is the Take as it is NOW, as on the Mac: an edit that landed
        // in the moment before the hold took effect must not be replaced by the older copy in
        // the queue. Only if it has gone does the queued copy stand in.
        var winner = keepLocal ? ((try? store.take(id: id)) ?? pair.local) : pair.remote
        // Stamp the resolution as a FRESH edit so the chosen version wins at the cloud
        // (owner-reported 2026-06-27). Without this the winner keeps its old `modifiedAt`,
        // which is ≤ the last-sync watermark — so `pushOutbound` never re-uploads it, the
        // divergent remote copy survives, and the next `pullInbound` re-detects the SAME
        // conflict via the `(localChanged:false, remoteChanged:false)` branch. Resolving
        // then never sticks: the conflict re-surfaces on every sync. Bumping `modifiedAt`
        // makes the next sync push the winner over the remote and the pull see `keepLocal`.
        winner.modifiedAt = Date()
        try store.upsert(winner)
        waiting.remove(at: idx)
        skipped.remove(id)
        waitingChanged()
        removeFile(id)
    }

    /// "Skip for now": hidden until the next launch or a newer version, nothing written. The
    /// Take stays held until the user chooses.
    func skip(id: UUID) {
        guard waiting.contains(where: { $0.local.id == id }) else { return }
        skipped.insert(id)
    }

    /// Show a skipped conflict again: the user tried to change a Take that is waiting for it.
    func reveal(id: UUID) {
        skipped.remove(id)
    }

    /// Hide every conflict and drop every unverified copy, writing nothing. Waiting Takes stay
    /// held. Used by tests.
    func dismissAll() {
        skipped.formUnion(waiting.map(\.local.id))
        unverified.removeAll()
    }

    /// The other device's version as a Take of its own: a new id, a new notification id for its
    /// reminder so the two never cancel each other, and never the Obie (as Core's
    /// `SyncEngine.fork` and the Mac's queue). Used to keep an edit made to a held Take.
    static func copy(of take: Take) -> Take {
        let id = UUID()
        var reminder = take.timeReminder
        reminder?.notificationIdentifier = id.uuidString
        return Take(id: id, createdAt: take.createdAt, modifiedAt: take.modifiedAt,
                    blocks: take.blocks, contentType: take.contentType, isNote: take.isNote,
                    isObie: false, timeReminder: reminder,
                    locationReminder: take.locationReminder, attachments: take.attachments,
                    isSeeded: false, isImportant: take.isImportant, manualOrder: take.manualOrder,
                    kind: take.kind, pageMode: take.pageMode)
    }

    // MARK: - On disk

    private struct Pair: Codable { let local: Take; let remote: Take }

    private func fileURL(_ id: UUID) -> URL? {
        directory?.appendingPathComponent(id.uuidString.lowercased()).appendingPathExtension("conflict")
    }

    /// Written on every enqueue. A failure leaves the conflict held in memory for this
    /// session and is recorded; it does not stop the sync that found it.
    private func persist(_ pair: (local: Take, remote: Take)) {
        guard let directory, let keys, let url = fileURL(pair.local.id) else { return }
        do {
            try Self.prepare(directory)
            try Self.seal(pair, keys: keys)
                .write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = url
            try mutable.setResourceValues(values)
        } catch {
            let ns = error as NSError
            DiagnosticsLog.shared.record(.conflictNotKept(domain: ns.domain, code: ns.code))
        }
    }

    private func removeFile(_ id: UUID) {
        guard let url = fileURL(id), FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) } catch {
            DiagnosticsLog.shared.record(.conflictFileNotRemoved)
        }
    }

    /// The folder takes the database's protection class and, like the database, stays out of
    /// backups: what it holds is sealed to keys a backup would not carry.
    private static func prepare(_ directory: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = directory
            try mutable.setResourceValues(values)
        }
    }

    static func seal(_ pair: (local: Take, remote: Take), keys: KeyHierarchy) throws -> Data {
        let plain = try PlatformJSON.encode(Pair(local: pair.local, remote: pair.remote))
        let id = pair.local.id
        let box = try AES.GCM.seal(plain, using: keys.itemKey(takeUUID: id),
                                   authenticating: format + Data(id.uuidString.utf8))
        guard let combined = box.combined else { throw CocoaError(.coderInvalidValue) }
        return combined
    }

    static func open(_ sealed: Data, id: UUID, keys: KeyHierarchy) throws -> (local: Take, remote: Take) {
        let box = try AES.GCM.SealedBox(combined: sealed)
        let plain = try AES.GCM.open(box, using: keys.itemKey(takeUUID: id),
                                     authenticating: format + Data(id.uuidString.utf8))
        let pair = try PlatformJSON.decode(Pair.self, from: plain)
        return (pair.local, pair.remote)
    }

    // MARK: - Unverified cloud copies (2026-09-30)
    //
    // A cloud copy that failed verification where only the user can settle it: the manifest
    // names a newer version than this device holds, or the Take is not on this device. The
    // engine never writes these locally; the user keeps this phone's version, keeps (recovers)
    // the cloud copy when it decrypted, or skips. In memory only and not held: the next sync
    // re-detects them.

    private(set) var unverified: [UnverifiedCopy] = []

    /// What the banner counts: two-version conflicts plus unverified copies.
    var attentionCount: Int { pending.count + unverified.count }

    /// Add unverified copies; an incoming item replaces a pending one for the same id.
    /// Never offered for a Take waiting for a conflict choice: keeping either copy writes the
    /// raw store, which would change a held Take.
    func enqueueUnverified(_ items: [UnverifiedCopy]) {
        guard accepting else { return }
        var added = 0
        for item in items where !isHeld(item.id) {
            if let idx = unverified.firstIndex(where: { $0.id == item.id }) {
                unverified[idx] = item
            } else {
                unverified.append(item)
                added += 1
            }
        }
        if added > 0 {
            DiagnosticsLog.shared.record(.conflictsUnverified(added))
        }
    }

    /// Keep this phone's version. Stamped as a fresh edit, like `resolve`, so the next push makes
    /// it the newest version and replaces the cloud copy; a newer edit on another device that
    /// could not be read is replaced when that device syncs.
    func keepPhone(id: UUID, store: TakeStore) throws {
        guard let idx = unverified.firstIndex(where: { $0.id == id }),
              var winner = unverified[idx].local else { return }
        winner.modifiedAt = Date()
        try store.upsert(winner)
        unverified.remove(at: idx)
    }

    /// Keep the cloud copy that decrypted: on the conflict screen beside this phone's version, or
    /// "Recover" for a Take not on this device. Stamped as a fresh edit so the next push re-uploads
    /// it and the cloud verifies again. No-op when nothing decrypted.
    func keepCloud(id: UUID, store: TakeStore) throws {
        guard let idx = unverified.firstIndex(where: { $0.id == id }),
              var winner = unverified[idx].cloud else { return }
        winner.modifiedAt = Date()
        try store.upsert(winner)
        unverified.remove(at: idx)
    }

    /// Skip for now: nothing written; the next sync re-surfaces it if still unresolved.
    func skipUnverified(id: UUID) {
        unverified.removeAll { $0.id == id }
    }
}
