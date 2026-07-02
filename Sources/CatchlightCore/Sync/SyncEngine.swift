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

public struct SyncReport: Equatable, Sendable {
    public var applied: [UUID] = []          // remote versions written to local
    public var conflicts: [(local: Take, remote: Take)] = []
    public var quarantined: [UUID] = []      // failed HMAC / undecryptable; not shown
    /// Declared in the manifest but not yet readable from the folder — almost
    /// always provider propagation lag or an evicted file. NOT an integrity
    /// signal; retried implicitly on the next sync pass.
    public var skipped: [UUID] = []
    public var deletedLocally: [UUID] = []   // remote tombstones applied locally
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
        a.skipped == b.skipped &&
        a.deletedLocally == b.deletedLocally &&
        a.uploaded == b.uploaded &&
        a.heldBack == b.heldBack &&
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
    public func pushOutbound(isCancelled: () -> Bool = { false }) throws -> SyncReport {
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
        if let data = try cloud.read(Manifest.fileName) {
            // FAIL CLOSED on an existing-but-bad manifest (2026-06-10): pushing
            // over an unverifiable or future-version manifest would silently
            // rebuild with empty carry-forward — dropping other devices'
            // not-yet-pulled entries and EVERY tombstone (resurrection), or
            // destructively downgrading a newer client's format. A genuinely
            // malformed manifest (unparseable JSON) gets the same treatment as
            // a bad signature: stop and surface, never overwrite.
            guard let prev = try? Manifest.parse(data) else {
                throw SyncError.manifestSignatureInvalid
            }
            guard Manifest.supportedVersions.contains(prev.version) else {
                throw SyncError.unsupportedManifestVersion(prev.version)
            }
            guard try signer.verify(prev) else {
                throw SyncError.manifestSignatureInvalid
            }
            for e in prev.takes { entries[e.uuid] = e }
            for t in prev.tombstones { mergedTombstones[t.uuid] = t }
        }

        // 1. Upload changed Takes. Blob HMACs are computed from the bytes in
        //    hand — no read-back.
        let changed = try store.takesModified(since: lastSync)
        for take in changed {
            if isCancelled() { throw CancellationError() }
            try upload(take, to: cloud, entries: &entries, report: &report)
        }

        // 2. Local tombstones: delete the blobs and merge the deletion records.
        //    Plain delete, not secureDelete — the overwrite pass was defeated by
        //    atomic-write semantics (new file + rename) and provider version
        //    history anyway, and doubled upload traffic per deletion. Blob
        //    confidentiality rests on AES-256-GCM, not on deletion hygiene.
        let localTombstones = try store.tombstones()
        for ts in localTombstones {
            if isCancelled() { throw CancellationError() }
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
        for take in localTakes where entries[take.id] == nil && !tombstonedIds.contains(take.id) {
            if isCancelled() { throw CancellationError() }
            if offlineTooLong, let lastSync, take.modifiedAt <= lastSync {
                report.heldBack.append(take.id)
                continue
            }
            try upload(take, to: cloud, entries: &entries, report: &report)
        }

        // 5. Sign + atomic write.
        let manifest = Manifest(
            updated: ISO8601.string(from: now()),
            schemaVersion: schemaVersion,
            takes: entries.values.sorted { $0.uuid.uuidString < $1.uuid.uuidString },
            tombstones: finalTombstones.sorted { $0.uuid.uuidString < $1.uuid.uuidString }
        )
        let signed = try signer.sign(manifest)
        try cloud.writeAtomically(try signed.serialise(), to: Manifest.fileName)

        // 6. Local tombstones are NOT purged here (2026-06-10). Two devices can
        //    pass the advisory lock during cloud propagation delay and the later
        //    manifest write clobbers the earlier one — if we purged now, a
        //    clobbered tombstone would never re-propagate (the deletion would
        //    silently resurrect). Tombstones are purged only when OBSERVED in a
        //    PULLED manifest (see pullInbound); until then each push idempotently
        //    re-merges them. Tombstones superseded by a local edit (edit-wins
        //    above) ARE purged — the live Take is authoritative.
        let supersededByEdit = localTombstones.map(\.id).filter { id in
            !tombstonedIds.contains(id) && localById[id] != nil
        }
        try store.purgeTombstones(ids: supersededByEdit)

        // 7. Watermark — the pre-query timestamp, NOT "now".
        store.setLastSyncDate(watermark)
        return report
    }

    private func upload(_ take: Take, to cloud: CloudFolder,
                        entries: inout [UUID: ManifestEntry],
                        report: inout SyncReport) throws {
        let sealed = try crypto.seal(take)
        let blob = CloudBlob(take: take, sealed: sealed)
        let bytes = try blob.serialise()
        try cloud.write(bytes, to: blob.fileName)
        entries[take.id] = ManifestEntry(
            uuid: take.id,
            modified: ISO8601.string(from: take.modifiedAt),
            hmac: signer.blobHMACHex(bytes)
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

        guard let manifestData = try cloud.read(Manifest.fileName) else {
            return report   // nothing remote yet
        }
        let manifest = try Manifest.parse(manifestData)

        // 0. Forward-compat guard — refuse to misread a future format as v1.
        guard Manifest.supportedVersions.contains(manifest.version) else {
            throw SyncError.unsupportedManifestVersion(manifest.version)
        }

        // 1. Verify manifest signature FIRST. Failure → quarantine everything.
        guard try signer.verify(manifest) else {
            throw SyncError.manifestSignatureInvalid
        }

        let lastSync = store.lastSyncDate()

        // 2. Apply tombstones (edit-wins by timestamp). A local edit made AFTER
        //    the deletion survives and will re-assert the Take on the next push.
        let tombstonedIds = Set(manifest.tombstones.map(\.uuid))
        for t in manifest.tombstones {
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
            let name = "\(entry.uuid.uuidString).clk"
            guard let blobBytes = try cloud.read(name) else {
                // Declared but not yet readable — provider propagation lag or an
                // evicted file. NOT an integrity failure; retried next pass.
                report.skipped.append(entry.uuid)
                continue
            }
            // Per-blob HMAC verification.
            guard signer.verifyBlob(blobBytes, expectedHex: entry.hmac) else {
                report.quarantined.append(entry.uuid)    // tampered/corrupted
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
                try store.upsert(t)
                report.applied.append(t.id)
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

    /// Convenience: pull then push (idempotent). Lock contention on the push
    /// half is a routine outcome and is reported via `pushDeferred`, not thrown
    /// — the pull half's results remain valid either way.
    @discardableResult
    public func sync(isCancelled: () -> Bool = { false }) throws -> SyncReport {
        var report = try pullInbound(isCancelled: isCancelled)
        do {
            let out = try pushOutbound(isCancelled: isCancelled)
            report.uploaded = out.uploaded
            report.heldBack = out.heldBack
        } catch is SyncLockError {
            report.pushDeferred = true
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
