//
//  SyncEngine.swift
//  CatchlightCore
//
//  The cloud-agnostic sync engine (Phase 5 brief §7). It is offline-first and
//  idempotent: running it repeatedly with the same state is safe, which is required
//  because iOS does not guarantee background-task timing (§7.8).
//
//  Outbound (local → cloud, §7.4): encrypt changed Takes to {uuid}.clk envelopes,
//  HMAC each, rebuild and re-sign the manifest, write the manifest atomically.
//
//  Inbound (cloud → local, §7.5): verify the manifest signature FIRST (failure
//  quarantines the entire batch and leaves the local DB untouched); then verify
//  each blob's HMAC (a single failure quarantines just that Take); then decrypt,
//  detect conflicts, and merge.
//
//  Local-only mode (§7.9): with no CloudFolder configured, no sync runs; all
//  encryption still operates on the local SQLCipher database normally. When a
//  folder is later configured, the first outbound run uploads every existing Take.
//

import Foundation

public struct SyncReport: Equatable, Sendable {
    public var applied: [UUID] = []          // remote versions written to local
    public var conflicts: [(local: Take, remote: Take)] = []
    public var quarantined: [UUID] = []      // failed HMAC; not decrypted, not shown
    public var deletedLocally: [UUID] = []   // remote deletions applied locally
    public var uploaded: [UUID] = []         // local versions written to cloud

    public static func == (a: SyncReport, b: SyncReport) -> Bool {
        a.applied == b.applied &&
        a.quarantined == b.quarantined &&
        a.deletedLocally == b.deletedLocally &&
        a.uploaded == b.uploaded &&
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
    private let argon2Salt: Data
    private let deviceId: UUID
    private let now: () -> Date

    public init(
        store: TakeStore,
        cloud: CloudFolder?,
        keys: KeyHierarchy,
        argon2Salt: Data,
        schemaVersion: Int = 1,
        appVersion: String = "1.0.0",
        deviceId: UUID = UUID(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.cloud = cloud
        self.crypto = TakeCrypto(keys: keys)
        self.signer = ManifestSigner(keys: keys)
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.argon2Salt = argon2Salt
        self.deviceId = deviceId
        self.now = now
    }

    public var isLocalOnly: Bool { cloud == nil }

    // MARK: - Outbound

    /// Encrypt locally changed Takes, mirror deletions, rebuild + re-sign manifest.
    @discardableResult
    public func pushOutbound() throws -> SyncReport {
        guard let cloud else { throw SyncError.noCloudFolderConfigured }
        try acquireLock(on: cloud)
        // Release on success OR failure — never leave a lock behind. NSFileCoordinator
        // serialises the underlying file operations on iOS (see FileCloudFolder).
        defer { try? releaseLock(on: cloud) }

        var report = SyncReport()

        ensureAccountMetadata(cloud)

        let localTakes = try store.allTakes()
        let localIds = Set(localTakes.map(\.id))
        let lastSync = store.lastSyncDate()

        // 1–2. Write changed blobs.
        let changed = try store.takesModified(since: lastSync)
        for take in changed {
            let sealed = try crypto.seal(take)
            let blob = CloudBlob(take: take, sealed: sealed)
            try cloud.write(try blob.serialise(), to: blob.fileName)
            report.uploaded.append(take.id)
        }

        // 3. Mirror local deletions: remove cloud .clk files with no local Take.
        for file in try cloud.clkFiles() {
            let uuidString = String(file.dropLast(4))   // strip ".clk"
            if let uuid = UUID(uuidString: uuidString), !localIds.contains(uuid) {
                try cloud.secureDelete(file)
            }
        }

        // 4. Build manifest entries from current cloud blob bytes (full index).
        var entries: [ManifestEntry] = []
        for take in localTakes {
            let name = "\(take.id.uuidString).clk"
            guard let blobBytes = try cloud.read(name) else { continue }
            entries.append(ManifestEntry(
                uuid: take.id,
                modified: ISO8601.string(from: take.modifiedAt),
                hmac: signer.blobHMACHex(blobBytes)
            ))
        }
        entries.sort { $0.uuid.uuidString < $1.uuid.uuidString }

        // 5. Sign + atomic write.
        let manifest = Manifest(
            updated: ISO8601.string(from: now()),
            schemaVersion: schemaVersion,
            takes: entries
        )
        let signed = try signer.sign(manifest)
        try cloud.writeAtomically(try signed.serialise(), to: Manifest.fileName)

        // 6. Watermark.
        store.setLastSyncDate(now())
        return report
    }

    // MARK: - Inbound

    /// Verify + merge remote changes. Never modifies local state if the manifest
    /// signature is invalid.
    @discardableResult
    public func pullInbound() throws -> SyncReport {
        guard let cloud else { throw SyncError.noCloudFolderConfigured }
        var report = SyncReport()

        guard let manifestData = try cloud.read(Manifest.fileName) else {
            return report   // nothing remote yet
        }
        let manifest = try Manifest.parse(manifestData)

        // 1. Verify manifest signature FIRST. Failure → quarantine everything.
        guard try signer.verify(manifest) else {
            throw SyncError.manifestSignatureInvalid
        }

        let lastSync = store.lastSyncDate()
        let remoteIds = Set(manifest.takes.map(\.uuid))

        // 2–5. Per-entry verify, decrypt, conflict-detect, merge.
        for entry in manifest.takes {
            let name = "\(entry.uuid.uuidString).clk"
            guard let blobBytes = try cloud.read(name) else {
                report.quarantined.append(entry.uuid)   // declared but missing
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
                guard let ct = blob.ciphertext else { throw SyncError.malformedEnvelope(entry.uuid) }
                remoteTake = try crypto.open(ct, takeUUID: entry.uuid)
            } catch {
                report.quarantined.append(entry.uuid)
                continue
            }

            let local = try store.take(id: entry.uuid)
            switch ConflictResolver.decide(local: local, remote: remoteTake, lastSync: lastSync) {
            case .takeRemote(let t):
                try store.upsert(t)
                report.applied.append(t.id)
            case .conflict(let l, let r):
                report.conflicts.append((local: l, remote: r))   // surfaced; Phase 6 UI resolves
            case .keepLocal, .noChange:
                break
            }
        }

        // 6. Remote deletions: a local Take absent from the remote manifest that
        // was NOT changed locally since last sync was deleted on another device.
        // (Local-changed-since-sync Takes are new/edited and pending upload — keep.)
        for local in try store.allTakes() where !remoteIds.contains(local.id) {
            let watermark = lastSync ?? .distantPast
            if local.modifiedAt <= watermark {
                try store.delete(id: local.id)
                report.deletedLocally.append(local.id)
            }
        }

        return report
    }

    /// Convenience: pull then push (idempotent).
    @discardableResult
    public func sync() throws -> SyncReport {
        var report = try pullInbound()
        let out = try pushOutbound()
        report.uploaded = out.uploaded
        return report
    }

    // MARK: - Lock file

    /// Acquire `catchlight.lock` in the cloud folder. Throws
    /// `SyncLockError.heldByOtherDevice` if a fresh lock from a different device is
    /// already present. A stale lock (>5 min) is overwritten. A lock previously
    /// orphaned by this same device is also overwritten (no-op recovery).
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
        // `try?` flattens `Data?` → binding succeeds only if the file already exists.
        if (try? cloud.read(name)) != nil { return }
        let meta = AccountMetadata(
            schemaVersion: schemaVersion,
            accountCreatedAt: ISO8601.string(from: now()),
            argon2Salt: argon2Salt.base64EncodedString(),
            appVersion: appVersion
        )
        if let data = try? PlatformJSON.encode(meta) {
            try? cloud.write(data, to: name)
        }
    }
}
