//
//  SyncEngine.swift
//  CatchlightCore
//
//  The cloud-agnostic sync engine (Phase 5 brief §7). It is offline-first and
//  idempotent: running it repeatedly with the same state is safe, which is required
//  because iOS does not guarantee background-task timing (§7.8).
//
//  Outbound (local → cloud, §7.4): encrypt changed Takes to {uuid}.clk envelopes,
//  HMAC each, merge the manifest forward (carrying unchanged entries' HMACs from
//  the previous verified manifest — no per-blob re-reads), record tombstones for
//  local deletions, sign, and write the manifest atomically.
//
//  Inbound (cloud → local, §7.5): verify the manifest signature FIRST (failure
//  quarantines the entire batch and leaves the local DB untouched); apply
//  tombstones (edit-wins by timestamp); then verify each blob's HMAC (a single
//  failure quarantines just that Take); then decrypt, detect conflicts, and merge.
//
//  DELETION MODEL (2026-06-10): deletions are propagated via explicit manifest
//  tombstones. The previous model inferred deletion from absence, which (a)
//  resurrected local deletions on the next pull, (b) turned transient blob-read
//  failures during manifest rebuild into authoritative fleet-wide deletions, and
//  (c) let one device delete another device's not-yet-pulled uploads. Absence
//  from the manifest now means "unknown here" — never "deleted".
//
//  WATERMARK (2026-06-10): captured BEFORE the changed-Takes query and persisted
//  after the push completes. Sampling it after the uploads finished meant any
//  edit made during the push window fell below the new watermark and was never
//  uploaded.
//
//  Local-only mode (§7.9): with no CloudFolder configured, no sync runs; all
//  encryption still operates on the local encrypted store normally. When a
//  folder is later configured, the first outbound run uploads every existing Take.
//

import Foundation
import CryptoKit

/// A Take whose cloud copy failed verification (its bytes no longer match the manifest's HMAC)
/// and which only the user can settle: the manifest names a newer version than this device holds,
/// or the Take is not on this device at all. Never written locally by the engine.
public struct UnverifiedCopy: Sendable {
    public let id: UUID
    /// This device's version; nil when the Take is not on this device.
    public let local: Take?
    /// The cloud copy as it decrypted, which may be an OLDER version than the manifest names;
    /// nil when it does not decrypt at all.
    public let cloud: Take?

    public init(id: UUID, local: Take?, cloud: Take?) {
        self.id = id
        self.local = local
        self.cloud = cloud
    }
}

public struct SyncReport: Equatable, Sendable {
    public var applied: [UUID] = []          // remote versions written to local
    public var conflicts: [(local: Take, remote: Take)] = []
    public var quarantined: [UUID] = []      // failed HMAC / undecryptable; not shown
    /// Cloud copies re-uploaded because they failed verification while this device held the very
    /// version the manifest names. Silent: there is nothing for the user to decide.
    public var repaired: [UUID] = []
    /// Cloud copies that failed verification and need the user (see `UnverifiedCopy`).
    public var unverified: [UnverifiedCopy] = []
    /// Pull → push hand-off inside `sync()`: copies this device can repair (it holds the exact
    /// version the manifest names). Push re-checks the version before it writes.
    var repairCandidates: [UUID] = []
    /// Declared in the manifest but not yet readable from the folder — almost
    /// always provider propagation lag or an evicted file. NOT an integrity
    /// signal; retried implicitly on the next sync pass.
    public var skipped: [UUID] = []
    /// Removed from this device by the pull: remote tombstones applied, and Takes another
    /// device turned into Scripts (D-315), which leave without a tombstone. Either way the
    /// app cancels their reminders.
    public var deletedLocally: [UUID] = []
    /// New Takes made from this device's edit of a Take that another device turned into a
    /// Script and edited too (D-315). Also listed in `applied`, so reminders are armed.
    public var forkedFromScripts: [UUID] = []
    public var uploaded: [UUID] = []         // local versions written to cloud
    /// Live local Takes push's self-heal step did NOT re-upload because this
    /// device was offline longer than the tombstone-retention window (2026-07-01):
    /// an unmatched old Take on such a device is indistinguishable from one the
    /// fleet deleted after we last synced, and auto-uploading it would resurrect
    /// the deletion everywhere. The user re-asserts a held-back Take by editing
    /// it (the bump re-uploads it via the normal changed-Takes path); the app
    /// surfaces the count as a notice.
    public var heldBack: [UUID] = []
    /// True when the push half was skipped because another device holds the sync
    /// lock. A routine, designed-for outcome — NOT a failure.
    public var pushDeferred: Bool = false

    public static func == (a: SyncReport, b: SyncReport) -> Bool {
        a.applied == b.applied &&
        a.quarantined == b.quarantined &&
        a.repaired == b.repaired &&
        a.unverified.map(\.id) == b.unverified.map(\.id) &&
        a.skipped == b.skipped &&
        a.deletedLocally == b.deletedLocally &&
        a.uploaded == b.uploaded &&
        a.heldBack == b.heldBack &&
        a.forkedFromScripts == b.forkedFromScripts &&
        a.pushDeferred == b.pushDeferred &&
        a.conflicts.map(\.local.id) == b.conflicts.map(\.local.id) &&
        a.conflicts.map(\.remote.id) == b.conflicts.map(\.remote.id)
    }
}

public final class SyncEngine {
    private let store: TakeStore
    private let cloud: CloudFolder?
    private let crypto: TakeCrypto
    private let signer: ManifestSigner
    /// Seals the manifest BODY (v3, owner 2026-08-11). Distinct from the signer's HMAC key —
    /// separate HKDF info strings, so authentication and confidentiality never share material.
    private let manifestKey: SymmetricKey
    private let schemaVersion: Int
    private let appVersion: String
    private let deviceId: UUID
    private let now: () -> Date

    /// - Parameter deviceId: REQUIRED stable per-install identifier. (Previously
    ///   defaulted to `UUID()`, which gave every engine instance a fresh identity
    ///   — its own orphaned lock then looked like another device's and blocked
    ///   sync for the full stale window.)
    public init(
        store: TakeStore,
        cloud: CloudFolder?,
        keys: KeyHierarchy,
        schemaVersion: Int = 1,
        appVersion: String = "1.0.0",
        deviceId: UUID,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.cloud = cloud
        self.crypto = TakeCrypto(keys: keys)
        self.signer = ManifestSigner(keys: keys)
        self.manifestKey = keys.manifestEncryptionKey()
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.deviceId = deviceId
        self.now = now
    }

    public var isLocalOnly: Bool { cloud == nil }

    // MARK: - Outbound

    /// Encrypt locally changed Takes, propagate deletions as tombstones, merge +
    /// re-sign the manifest.
    /// - Parameter isCancelled: cooperative cancellation seam (BGTask expiry).
    @discardableResult
    public func pushOutbound(isCancelled: () -> Bool = { false },
                             repairing repairIDs: Set<UUID> = []) throws -> SyncReport {
        guard let cloud else { throw SyncError.noCloudFolderConfigured }
        try acquireLock(on: cloud)
        // Release on success OR failure — never leave a lock behind.
        defer { try? releaseLock(on: cloud) }

        var report = SyncReport()

        ensureAccountMetadata(cloud)

        // Watermark captured BEFORE the changed-Takes query (see header).
        let watermark = now()
        let lastSync = store.lastSyncDate()

        // Previous VERIFIED manifest: unchanged entries' HMACs carry forward, so
        // a push touches only the blobs it actually writes. (Previously every
        // push re-read and re-HMACed every blob in the folder — O(n) coordinated
        // file reads per pass — and silently DROPPED entries whose blob wasn't
        // readable, which other devices then interpreted as deletions.)
        var entries: [UUID: ManifestEntry] = [:]
        var mergedTombstones: [UUID: ManifestTombstone] = [:]
        // FAIL CLOSED on an existing-but-bad manifest (2026-06-10): pushing over an
        // unverifiable or future-version manifest would silently rebuild with empty
        // carry-forward — dropping other devices' not-yet-pulled entries and EVERY tombstone
        // (resurrection), or destructively downgrading a newer client's format. A genuinely
        // malformed manifest gets the same treatment as a bad signature: stop and surface,
        // never overwrite. `readVerifiedManifest` throws on every one of those; a nil return
        // means only "no manifest yet".
        if let prev = try readVerifiedManifest(from: cloud) {
            for e in prev.takes { entries[e.uuid] = e }
            for t in prev.tombstones { mergedTombstones[t.uuid] = t }
        }
        // The folder's entries as they were BEFORE this push wrote anything. The D-315 guards
        // compare against these: an entry this push has just uploaded is our own write, not
        // an edit from elsewhere.
        let entriesBeforePush = entries

        // 1. Upload changed Takes. Blob HMACs are computed from the bytes in
        //    hand — no read-back.
        let changed = try store.takesModified(since: lastSync)
        for take in changed {
            if isCancelled() { throw CancellationError() }
            // Never upload over a Script holding an edit this device has not seen (D-315):
            // keep this edit as a new Take instead, uploaded now.
            if let e = entriesBeforePush[take.id], Self.changedElsewhere(e, since: lastSync) {
                try forkAndUpload(take, to: cloud, entries: &entries, report: &report)
                continue
            }
            try upload(take, to: cloud, entries: &entries, report: &report)
        }

        // 2. Local tombstones: delete the blobs and merge the deletion records.
        //    Plain delete, not secureDelete — the overwrite pass was defeated by
        //    atomic-write semantics (new file + rename) and provider version
        //    history anyway, and doubled upload traffic per deletion. Blob
        //    confidentiality rests on AES-256-GCM, not on deletion hygiene.
        //    The phone never deletes a Script (D-325). A Take deleted here that another
        //    device has since turned into a Script is gone from this device only: its file
        //    and entry are left alone, and the deletion record is dropped (step 6) rather
        //    than sent, because from here the Take simply no longer exists.
        let localTombstones = try store.tombstones()
        var deletionsOfScripts: [UUID] = []
        for ts in localTombstones {
            if isCancelled() { throw CancellationError() }
            if let e = entriesBeforePush[ts.id], !e.isTake {
                deletionsOfScripts.append(ts.id)
                continue
            }
            try? cloud.delete("\(ts.id.uuidString).clk")
            let incoming = ManifestTombstone(uuid: ts.id, deletedAt: ISO8601.string(from: ts.deletedAt))
            if let existing = mergedTombstones[ts.id],
               (ISO8601.date(from: existing.deletedAt) ?? .distantPast) >= ts.deletedAt {
                // keep the existing (newer) record
            } else {
                mergedTombstones[ts.id] = incoming
            }
        }

        // 3. Resolve tombstones against live local Takes (edit-wins by
        //    timestamp) and prune records past retention.
        let localTakes = try store.allTakes()
        let localById = Dictionary(uniqueKeysWithValues: localTakes.map { ($0.id, $0) })
        var finalTombstones: [ManifestTombstone] = []
        for (id, t) in mergedTombstones {
            // A deletion from anywhere never removes an entry that is no longer a Take
            // (D-325): the Script stays and the record goes.
            if let e = entries[id], !e.isTake { continue }
            let deletedAt = ISO8601.date(from: t.deletedAt) ?? .distantPast
            if let local = localById[id], local.modifiedAt > deletedAt {
                continue   // edited after deletion → the edit wins; entry stays
            }
            if now().timeIntervalSince(deletedAt) > Manifest.tombstoneRetention {
                continue   // every device has had ample time to observe it
            }
            // If the manifest still listed a live entry for this id (a MERGED
            // remote tombstone beating a blob we or another device uploaded),
            // delete the blob too (2026-07-01) — step 2 only deletes blobs for
            // LOCAL tombstones, so this case left an orphaned .clk in the folder
            // forever. Guarded on the entry so it runs once, not on every push
            // for the tombstone's whole retention life.
            if entries[id] != nil {
                try? cloud.delete("\(id.uuidString).clk")
            }
            entries[id] = nil
            finalTombstones.append(t)
        }
        let tombstonedIds = Set(finalTombstones.map(\.uuid))

        // 4. Self-heal: any live local Take with no manifest entry (e.g. an
        //    upload missed by an earlier watermark race) is uploaded now.
        //
        //    LONG-OFFLINE GUARD (2026-07-01): if this device hasn't synced within
        //    the tombstone-retention window, an unmatched OLD Take (not modified
        //    since our last sync) is ambiguous — a missed upload, or a Take the
        //    fleet deleted whose tombstone has since been pruned. Auto-uploading
        //    it would resurrect the deletion fleet-wide, which is exactly what
        //    the tombstone model exists to prevent. Such Takes are HELD BACK and
        //    reported (`report.heldBack`); the user re-asserts one by editing it
        //    (the modifiedAt bump re-uploads it via step 1 next pass). A Take
        //    edited since last sync is never held back — edit-wins.
        let offlineTooLong = lastSync.map {
            now().timeIntervalSince($0) > Manifest.tombstoneRetention
        } ?? false
        //    STALE ENTRIES TOO (2026-09-03, D-250). This step used to require the entry to
        //    be ABSENT. Step 1 selects by `modifiedAt > lastSync`, so a Take whose local
        //    change survived one push cycle — a deferred lock, suspension mid-push, anything
        //    that let `setLastSyncDate` advance past it — was selected by NEITHER path. Its
        //    cloud copy then stayed wrong permanently and every pull re-raised it as a
        //    conflict. Observed on device: 4 Takes stuck across 15 hours and three launches,
        //    each immediately preceded by `Sync: push ok`.
        //
        //    A NEWER entry is deliberately left alone. If the cloud holds a more recent
        //    version than we do, another device wrote it and we have not pulled it yet;
        //    overwriting it here would silently discard their edit, which this engine must
        //    never do (see this file's header contract).
        //
        //    The long-offline hold-back stays scoped to the ABSENT case, unchanged. It exists
        //    because an unmatched Take may have been deleted fleet-wide with its tombstone
        //    since pruned — but an entry that EXISTS is proof the fleet still lists the Take,
        //    so there is no deletion to resurrect and nothing to hold back for.
        for take in localTakes where !tombstonedIds.contains(take.id) {
            if isCancelled() { throw CancellationError() }
            if let entry = entries[take.id] {
                if let before = entriesBeforePush[take.id],
                   Self.changedElsewhere(before, since: lastSync) {   // D-315, as step 1
                    // Only an edit newer than the last sync needs keeping; anything older is
                    // superseded by the Script, and the next pull lets it go.
                    if take.modifiedAt > (lastSync ?? .distantPast) {
                        try forkAndUpload(take, to: cloud, entries: &entries, report: &report)
                    }
                    continue
                }
                // REPAIR (2026-09-30): the pull found this Take's cloud copy failing verification
                // while this device holds the very version the manifest names. Re-uploading it
                // restores exactly what the manifest promises. Re-checked here, not trusted from
                // the pull: if the entry moved on in between, this is no longer the same version.
                if repairIDs.contains(take.id), ISO8601.string(from: take.modifiedAt) == entry.modified {
                    try upload(take, to: cloud, entries: &entries, report: &report)
                    report.repaired.append(take.id)
                    continue
                }
                // Rewrite only when the cloud copy is demonstrably older. An unparseable
                // date in a signed manifest makes the entry unusable, so local wins there
                // too rather than the Take being stranded behind a value nothing can read.
                let cloudModified = ISO8601.date(from: entry.modified)
                if let cloudModified, take.modifiedAt <= cloudModified { continue }
                try upload(take, to: cloud, entries: &entries, report: &report)
            } else {
                if offlineTooLong, let lastSync, take.modifiedAt <= lastSync {
                    report.heldBack.append(take.id)
                    continue
                }
                try upload(take, to: cloud, entries: &entries, report: &report)
            }
        }

        // 5. Sign + atomic write.
        let manifest = Manifest(
            updated: ISO8601.string(from: now()),
            schemaVersion: schemaVersion,
            takes: entries.values.sorted { $0.uuid.uuidString < $1.uuid.uuidString },
            tombstones: finalTombstones.sorted { $0.uuid.uuidString < $1.uuid.uuidString }
        )
        try writeManifest(manifest, to: cloud)

        // 6. Local tombstones are NOT purged here (2026-06-10). Two devices can
        //    pass the advisory lock during cloud propagation delay and the later
        //    manifest write clobbers the earlier one — if we purged now, a
        //    clobbered tombstone would never re-propagate (the deletion would
        //    silently resurrect). Tombstones are purged only when OBSERVED in a
        //    PULLED manifest (see pullInbound); until then each push idempotently
        //    re-merges them. Tombstones superseded by a local edit (edit-wins
        //    above) ARE purged — the live Take is authoritative — and so are deletions of
        //    Takes that became Scripts (step 2): they were never sent, so nothing can be
        //    clobbered, and keeping them would only re-skip them on every push.
        let supersededByEdit = localTombstones.map(\.id).filter { id in
            !tombstonedIds.contains(id) && localById[id] != nil
        }
        try store.purgeTombstones(ids: supersededByEdit + deletionsOfScripts)

        // 7. Watermark — the pre-query timestamp, NOT "now".
        store.setLastSyncDate(watermark)
        return report
    }

    /// Read + verify the manifest, whatever version is in the folder (owner 2026-08-11).
    ///
    /// ONE place routes v1/v2 (plain JSON) versus v3 (encrypted envelope), because the push
    /// path reads the previous manifest too and a second copy of this branch is exactly how
    /// the two would drift. Returns nil when the folder has no manifest yet.
    ///
    /// Fails closed on every unhappy path — unreadable, unsupported version, bad signature —
    /// so the callers' existing `manifestSignatureInvalid` handling is unchanged.
    private func readVerifiedManifest(from cloud: CloudFolder) throws -> Manifest? {
        guard let data = try cloud.read(Manifest.fileName) else { return nil }

        // The version is readable WITHOUT the key in both forms, which is what makes the
        // fail-closed gate reachable at all on an encrypted manifest.
        guard let version = ManifestEnvelope.peekVersion(data),
              Manifest.supportedVersions.contains(version) else {
            throw SyncError.unsupportedManifestVersion(ManifestEnvelope.peekVersion(data) ?? -1)
        }

        if version >= 3 {
            let envelope = try ManifestEnvelope.parse(data)
            guard try signer.verify(envelope) else { throw SyncError.manifestSignatureInvalid }
            return try Manifest.opening(envelope, with: manifestKey)
        }
        // v1 / v2 — plaintext, written by an earlier build. Still readable so a tester's
        // folder keeps syncing; the next push rewrites it as v3.
        let manifest = try Manifest.parse(data)
        guard try signer.verify(manifest) else { throw SyncError.manifestSignatureInvalid }
        return manifest
    }

    /// Seal, sign and write the manifest as v3. The only writer — a plaintext manifest can
    /// no longer be produced by any path.
    private func writeManifest(_ manifest: Manifest, to cloud: CloudFolder) throws {
        let envelope = try signer.sign(try manifest.sealed(with: manifestKey))
        try cloud.writeAtomically(try envelope.serialise(), to: Manifest.fileName)
    }

    /// True when a non-Take entry may hold another device's edit this one has not seen: it was
    /// written after our last sync, or there is no last sync to compare with, or its stamp does
    /// not parse. Uploading over such an entry would discard that edit (D-315).
    static func changedElsewhere(_ entry: ManifestEntry, since lastSync: Date?) -> Bool {
        guard !entry.isTake else { return false }
        guard let lastSync, let modified = ISO8601.date(from: entry.modified) else { return true }
        return modified > lastSync
    }

    /// Keep this device's edit as a new Take and let the original go (D-315, both sides
    /// changed). Returns the copy, or nil when the original was edited again in between (the
    /// copy is then withdrawn and a later pass tries again).
    ///
    /// The copy gets a fresh id, and its reminder a fresh notification id, so the original's
    /// reminder can be cancelled without touching the copy's. It is written as an ordinary
    /// Take FIRST and takes over the Obie only after the original is gone: writing it as an
    /// Obie straight away would demote the original and bump its timestamp, the release would
    /// then refuse, and the Obie would be lost. A crash between the steps can cost the Obie
    /// marker, never the text.
    @discardableResult
    private func fork(_ local: Take, into report: inout SyncReport) throws -> Take? {
        let id = UUID()
        var reminder = local.timeReminder
        reminder?.notificationIdentifier = id.uuidString
        let copy = Take(id: id, createdAt: local.createdAt, modifiedAt: local.modifiedAt,
                        blocks: local.blocks, contentType: local.contentType, isNote: local.isNote,
                        isObie: false, timeReminder: reminder,
                        locationReminder: local.locationReminder, attachments: local.attachments,
                        isSeeded: false, isImportant: local.isImportant, manualOrder: local.manualOrder)
        try store.upsert(copy)
        guard try store.release(id: local.id, ifNotModifiedAfter: local.modifiedAt) else {
            _ = try store.release(id: id, ifNotModifiedAfter: copy.modifiedAt)
            return nil
        }
        if local.isObie { try store.setObie(id: id, replaceExisting: true) }
        report.deletedLocally.append(local.id)
        report.applied.append(id)
        report.forkedFromScripts.append(id)
        return try store.take(id: id)
    }

    /// Push's side of the same rule. A push can run without a pull first, and it advances the
    /// watermark: an edit it merely skipped would then look synced, and the next pull would let
    /// the Take go and lose it. So push forks it here and uploads the copy in the same pass.
    private func forkAndUpload(_ take: Take, to cloud: CloudFolder,
                               entries: inout [UUID: ManifestEntry],
                               report: inout SyncReport) throws {
        if let copy = try fork(take, into: &report) {
            try upload(copy, to: cloud, entries: &entries, report: &report)
        }
    }

    private func upload(_ take: Take, to cloud: CloudFolder,
                        entries: inout [UUID: ManifestEntry],
                        report: inout SyncReport) throws {
        let sealed = try crypto.seal(take)
        let blob = CloudBlob(take: take, sealed: sealed)
        let bytes = try blob.serialise()
        try cloud.write(bytes, to: CloudBlob.fileName(for: take.id))
        // The entry's kind is kept (D-315): this device never turns a Script back into a
        // Take by uploading over it.
        entries[take.id] = ManifestEntry(
            uuid: take.id,
            modified: ISO8601.string(from: take.modifiedAt),
            hmac: signer.blobHMACHex(bytes),
            kind: entries[take.id]?.kind
        )
        report.uploaded.append(take.id)
    }

    // MARK: - Inbound

    /// Verify + merge remote changes. Never modifies local state if the manifest
    /// signature is invalid.
    @discardableResult
    public func pullInbound(isCancelled: () -> Bool = { false }) throws -> SyncReport {
        guard let cloud else { throw SyncError.noCloudFolderConfigured }
        var report = SyncReport()

        // Reads whichever version is in the folder, gates it, verifies the signature FIRST,
        // and decrypts a v3 body — all fail-closed. nil means nothing remote yet.
        guard let manifest = try readVerifiedManifest(from: cloud) else {
            return report
        }

        let lastSync = store.lastSyncDate()

        // 2. Apply tombstones (edit-wins by timestamp). A local edit made AFTER
        //    the deletion survives and will re-assert the Take on the next push.
        //    A deletion record never applies to an id the folder lists as a Script (D-325),
        //    as on push: the Script rules in step 3 decide what happens to the phone's copy,
        //    so an unsynced edit is forked rather than deleted.
        let scriptIds = Set(manifest.takes.filter { !$0.isTake }.map(\.uuid))
        let tombstonedIds = Set(manifest.tombstones.map(\.uuid)).subtracting(scriptIds)
        for t in manifest.tombstones where !scriptIds.contains(t.uuid) {
            if isCancelled() { throw CancellationError() }
            let deletedAt = ISO8601.date(from: t.deletedAt) ?? .distantPast
            if let local = try store.take(id: t.uuid), local.modifiedAt <= deletedAt {
                try store.delete(id: t.uuid)
                // (The delete just recorded a fresh local tombstone; the purge
                // below removes it — the manifest already carries the record.)
                try store.purgeTombstones(ids: [t.uuid])
                report.deletedLocally.append(t.uuid)
            }
        }

        // 2b. Purge local pending tombstones now OBSERVED in a pulled manifest
        //     (2026-06-10). Push deliberately does NOT purge after writing —
        //     a concurrent device's manifest write can clobber ours during
        //     cloud propagation, and a purged-but-clobbered tombstone would
        //     never re-propagate (silent resurrection). Observation in a pulled
        //     manifest is the durable confirmation. Only purge when the
        //     manifest's record is at least as new as ours.
        let pendingLocal = try store.tombstones()
        // A LOCAL deletion that hasn't been pushed yet (the cloud manifest still lists the
        // Take, with no tombstone). The push half of this same sync will propagate it; the
        // pull half below must NOT resurrect it in the meantime (see step 3).
        let pendingTombstoneByID = Dictionary(pendingLocal.map { ($0.id, $0.deletedAt) },
                                              uniquingKeysWith: { first, _ in first })
        if !pendingLocal.isEmpty {
            let remoteTombstones = Dictionary(uniqueKeysWithValues: manifest.tombstones.map { ($0.uuid, $0) })
            let confirmed = pendingLocal.filter { local in
                guard let remote = remoteTombstones[local.id],
                      let remoteDeletedAt = ISO8601.date(from: remote.deletedAt) else { return false }
                return remoteDeletedAt >= local.deletedAt
            }
            try store.purgeTombstones(ids: confirmed.map(\.id))
        }

        // 3–6. Per-entry verify, decrypt, conflict-detect, merge.
        for entry in manifest.takes where !tombstonedIds.contains(entry.uuid) {
            if isCancelled() { throw CancellationError() }
            // NOT A TAKE (D-315). A Script, or a kind from a newer client, is NEVER fetched or
            // shown here, in any branch; push carries its entry forward untouched.
            //   • Another device turned a Take this phone holds into a Script, and the phone has
            //     not edited it since the last sync: let it go, with no tombstone (nothing was
            //     deleted). Reported as `deletedLocally` so the app cancels its reminders.
            //   • The phone HAS edited it since, and the Script has not changed since: keep the
            //     edit; push sends it into the Script (kind kept) and a later pass lets it go.
            //   • Both have changed: neither side's work may be lost, and the Script must not be
            //     read here. The phone's edit is kept as a NEW Take (`forkedFromScripts`), the
            //     original is let go, and the Script stays exactly as the other device left it.
            if !entry.isTake {
                if let lastSync, try store.release(id: entry.uuid, ifNotModifiedAfter: lastSync) {
                    report.deletedLocally.append(entry.uuid)
                    continue
                }
                guard let local = try store.take(id: entry.uuid) else { continue }
                if Self.changedElsewhere(entry, since: lastSync) {
                    try fork(local, into: &report)
                }
                continue
            }
            let name = "\(entry.uuid.uuidString).clk"
            guard let blobBytes = try cloud.read(name) else {
                // Declared but not yet readable — provider propagation lag or an
                // evicted file. NOT an integrity failure; retried next pass.
                report.skipped.append(entry.uuid)
                continue
            }
            // Per-blob HMAC verification.
            guard signer.verifyBlob(blobBytes, expectedHex: entry.hmac) else {
                try classifyUnverified(entry, blobBytes: blobBytes,
                                       pendingTombstones: pendingTombstoneByID, into: &report)
                continue
            }
            let blob: CloudBlob
            let remoteTake: Take
            do {
                blob = try CloudBlob.parse(blobBytes)
                // Forward-compat guard (2026-07-01): a future-version envelope may
                // have changed semantics — quarantine it (retried once this client
                // is updated) rather than silently misreading it as v1. The
                // manifest has had this guard both directions from the start.
                guard CloudBlob.supportedVersions.contains(blob.version) else {
                    throw SyncError.malformedEnvelope(entry.uuid)
                }
                guard let ct = blob.ciphertext else { throw SyncError.malformedEnvelope(entry.uuid) }
                remoteTake = try crypto.open(ct, takeUUID: entry.uuid)
            } catch {
                report.quarantined.append(entry.uuid)
                continue
            }

            let local = try store.take(id: entry.uuid)
            // RESURRECTION GUARD (2026-06-21): the Take is absent locally because we
            // DELETED it and that tombstone hasn't reached the cloud yet — so the manifest
            // still lists it with no tombstone. Without this, `ConflictResolver` reads
            // `local == nil` as "new from another device" and re-creates it, and the
            // re-creating `upsert` clears our pending tombstone — the deletion can then
            // NEVER propagate (pull runs before push every sync). Skip it; the push half
            // records the manifest tombstone and deletes the blob. Edit-wins is preserved:
            // a remote version edited STRICTLY AFTER our deletion still resurrects.
            if local == nil,
               let deletedAt = pendingTombstoneByID[entry.uuid],
               deletedAt >= remoteTake.modifiedAt {
                continue
            }
            switch ConflictResolver.decide(local: local, remote: remoteTake, lastSync: lastSync) {
            case .takeRemote(let t):
                // RESURRECTION GUARD, part 2 (2026-07-23): the guard above consults
                // `pendingTombstoneByID`, a snapshot taken at pull-start — a delete
                // committed MID-PULL is invisible to it, and a plain `upsert` here
                // would re-create the Take AND clear its fresh tombstone (the
                // delete-resurrection bug). `applyRemote` re-checks tombstones
                // atomically with the write (the same store critical section a
                // concurrent `delete` uses), so the freshest deletion always wins
                // ties; a remote edit strictly after it still lands.
                if try store.applyRemote(t) {
                    report.applied.append(t.id)
                }
            case .conflict(let l, let r):
                report.conflicts.append((local: l, remote: r))   // surfaced; UI resolves
            case .keepLocal, .noChange:
                break
            }
        }

        // NOTE: deletion-by-absence is intentionally GONE. A local Take absent
        // from the manifest is uploaded by the next push, never deleted.
        return report
    }

    /// A cloud copy whose bytes no longer match the manifest's HMAC — most often a provider that
    /// kept an older file after two writes to the same path collided. It used to be quarantined on
    /// every pull, forever, unless the user happened to edit the Take (the owner's rules for what
    /// happens instead, 2026-09-30):
    ///
    ///   • this device holds the version the manifest names → repair: push re-uploads it on the
    ///     same sync, silently;
    ///   • this device holds a NEWER version → nothing to do: push uploads it anyway;
    ///   • the manifest names a newer version than this device holds, or the Take is not here →
    ///     `unverified`, for the user to decide, with the cloud copy attached when it decrypts;
    ///   • not here and unreadable, or written by a newer envelope version → quarantined.
    ///
    /// Nothing unverified is ever written locally here. AES-GCM authenticates the ciphertext, so
    /// a copy that decrypts is this user's own content; it may still be an older version.
    private func classifyUnverified(_ entry: ManifestEntry, blobBytes: Data,
                                    pendingTombstones: [UUID: Date],
                                    into report: inout SyncReport) throws {
        let local = try store.take(id: entry.uuid)
        // Deleted here and not yet pushed: push propagates the deletion; never offer it back.
        if local == nil, pendingTombstones[entry.uuid] != nil { return }

        let cloudTake: Take?
        if let blob = try? CloudBlob.parse(blobBytes) {
            // A newer client's envelope may carry semantics this one cannot read; routing it to
            // the user could overwrite that client's data, so it stays quarantined as before.
            guard CloudBlob.supportedVersions.contains(blob.version) else {
                report.quarantined.append(entry.uuid)
                return
            }
            cloudTake = blob.ciphertext.flatMap { try? crypto.open($0, takeUUID: entry.uuid) }
        } else {
            cloudTake = nil
        }

        if let local {
            if ISO8601.string(from: local.modifiedAt) == entry.modified {
                report.repairCandidates.append(entry.uuid)
                return
            }
            if let entryModified = ISO8601.date(from: entry.modified), local.modifiedAt > entryModified {
                return   // a newer local edit: push step 1 or 4 uploads it
            }
            report.unverified.append(UnverifiedCopy(id: entry.uuid, local: local, cloud: cloudTake))
        } else if let cloudTake {
            report.unverified.append(UnverifiedCopy(id: entry.uuid, local: nil, cloud: cloudTake))
        } else {
            report.quarantined.append(entry.uuid)
        }
    }

    /// Convenience: pull then push (idempotent). Lock contention on the push
    /// half is a routine outcome and is reported via `pushDeferred`, not thrown
    /// — the pull half's results remain valid either way.
    ///
    /// Each half records a content-free diagnostics line (D-085). Counts and UUIDs are
    /// deliberately EXCLUDED: the log is built to be attached to a bug report, and a Take
    /// count would disclose in plain text exactly what the v3 encrypted manifest exists to
    /// conceal — how many Takes the folder holds. Failures are logged by NSError domain and
    /// code only, mirroring `BackgroundSync`, because a `SyncError` carries a Take UUID in
    /// its associated value and interpolating its description would leak one.
    ///
    /// Successes alone would not be enough: without the failure lines, "sync never ran" and
    /// "sync ran and threw" look identical in the log, which is the exact ambiguity these
    /// entries exist to remove (2026-09-02 — a no-op-save conflict took hours to diagnose
    /// because pushes left no trace at all).
    @discardableResult
    public func sync(isCancelled: () -> Bool = { false }) throws -> SyncReport {
        var report: SyncReport
        do {
            report = try pullInbound(isCancelled: isCancelled)
        } catch {
            let ns = error as NSError
            DiagnosticsLog.shared.record(.lifecycle, "Sync: pull failed (\(ns.domain) \(ns.code))")
            throw error
        }
        DiagnosticsLog.shared.record(.lifecycle, "Sync: pull ok")
        do {
            let out = try pushOutbound(isCancelled: isCancelled,
                                       repairing: Set(report.repairCandidates))
            report.uploaded = out.uploaded
            report.heldBack = out.heldBack
            report.repaired = out.repaired
            // Push can fork too (D-315: a conversion landing between the halves). Its local
            // changes must reach the app like the pull's, or the original's reminder stays
            // armed and the copy's is never armed.
            report.deletedLocally += out.deletedLocally
            report.applied += out.applied
            report.forkedFromScripts += out.forkedFromScripts
            // Content-free, like the lines above: no count, no UUID.
            if !out.repaired.isEmpty {
                DiagnosticsLog.shared.record(.lifecycle, "Sync: repaired a cloud copy that failed verification")
            }
            DiagnosticsLog.shared.record(.lifecycle, "Sync: push ok")
        } catch is SyncLockError {
            report.pushDeferred = true
            DiagnosticsLog.shared.record(.lifecycle, "Sync: push deferred (lock held)")
        } catch {
            let ns = error as NSError
            DiagnosticsLog.shared.record(.lifecycle, "Sync: push failed (\(ns.domain) \(ns.code))")
            throw error
        }
        return report
    }

    // MARK: - Lock file

    /// Acquire `catchlight.lock` in the cloud folder. Throws
    /// `SyncLockError.heldByOtherDevice` if a fresh lock from a different device is
    /// already present. A stale lock (>5 min) is overwritten. A lock previously
    /// orphaned by this same device is also overwritten (no-op recovery).
    ///
    /// After writing, the lock is READ BACK: if another device's write landed in
    /// the same window, back off rather than proceeding on a stolen lock. The
    /// lock remains advisory across cloud propagation delays — the tombstone
    /// deletion model (not the lock) is what makes concurrent pushes safe.
    func acquireLock(on cloud: CloudFolder) throws {
        let nowDate = now()
        if let data = try cloud.read(SyncLock.fileName),
           let existing = try? PlatformJSON.decode(SyncLock.self, from: data) {
            let isOurs = existing.deviceId == deviceId
            if !isOurs && !existing.isStale(now: nowDate) {
                throw SyncLockError.heldByOtherDevice(holder: existing.deviceId, retryAfterSeconds: 45)
            }
            // Fall through and overwrite: stale lock OR our own previously-orphaned lock.
        }
        let lock = SyncLock(deviceId: deviceId, acquiredAt: ISO8601.string(from: nowDate))
        try cloud.write(try PlatformJSON.encode(lock), to: SyncLock.fileName)

        // Read-back verification.
        if let data = try cloud.read(SyncLock.fileName),
           let current = try? PlatformJSON.decode(SyncLock.self, from: data),
           current.deviceId != deviceId {
            throw SyncLockError.heldByOtherDevice(holder: current.deviceId, retryAfterSeconds: 45)
        }
    }

    /// Release `catchlight.lock`. No-op if missing or owned by another device
    /// (defence against deleting a fresh lock acquired between our acquire and
    /// release because a stale-window overlapped).
    func releaseLock(on cloud: CloudFolder) throws {
        guard let data = try cloud.read(SyncLock.fileName),
              let lock = try? PlatformJSON.decode(SyncLock.self, from: data),
              lock.deviceId == deviceId else {
            return
        }
        try cloud.delete(SyncLock.fileName)
    }

    // MARK: - Account metadata

    private func ensureAccountMetadata(_ cloud: CloudFolder) {
        let name = "catchlight-account-metadata.json"
        // Only write when the file is confirmed ABSENT (read returned nil). A
        // read ERROR must not be treated as absence — rewriting on a transient
        // I/O failure would clobber the original accountCreatedAt.
        do {
            if try cloud.read(name) != nil { return }
        } catch {
            return
        }
        let meta = AccountMetadata(
            schemaVersion: schemaVersion,
            accountCreatedAt: ISO8601.string(from: now()),
            appVersion: appVersion
        )
        if let data = try? PlatformJSON.encode(meta) {
            try? cloud.write(data, to: name)
        }
    }
}
