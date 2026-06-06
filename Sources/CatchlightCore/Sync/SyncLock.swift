//
//  SyncLock.swift
//  CatchlightCore
//
//  Lock-file serialisation for the cloud sync flow (Phase 5 brief §7.10).
//
//  Two devices writing to the cloud folder at the same time can produce torn
//  manifests and conflict-class problems that resolution logic shouldn't need to
//  solve. A single advisory lock file (`catchlight.lock`) in the cloud folder is
//  the cheap, file-system-native serialisation: a device that wants to push reads
//  the lock first, writes its own if absent (or stale), then deletes it on
//  completion. iOS file coordination (`NSFileCoordinator`) provides the underlying
//  read/write atomicity — this layer just expresses the policy.
//
//  The lock is ADVISORY, not authoritative: a determined attacker with cloud-folder
//  write access could ignore it. The encryption layer (per-item AES-GCM + manifest
//  HMAC) is what actually guarantees integrity. The lock only prevents *honest
//  clients* from stepping on each other.
//

import Foundation

/// Persisted contents of `catchlight.lock`. Cross-platform JSON; future Web /
/// Android clients must produce the same shape.
public struct SyncLock: Codable, Equatable, Sendable {
    /// Stable per-install device UUID (lives in `UserDefaults` on iOS).
    public let deviceId: UUID
    /// ISO-8601 millisecond-precision timestamp the lock was acquired.
    public let acquiredAt: String

    public static let fileName = "catchlight.lock"

    /// Locks older than this are treated as stale (crashed session) and may be
    /// overwritten. 5 minutes is generous for a normal sync round-trip but short
    /// enough that a crashed device doesn't block sync indefinitely.
    public static let staleAfter: TimeInterval = 5 * 60

    public init(deviceId: UUID, acquiredAt: String) {
        self.deviceId = deviceId
        self.acquiredAt = acquiredAt
    }

    /// True if `now` is at least `staleAfter` seconds past `acquiredAt`. Returns
    /// `true` for malformed timestamps so a corrupt lock never wedges sync forever.
    public func isStale(now: Date) -> Bool {
        guard let acquired = ISO8601.date(from: acquiredAt) else { return true }
        return now.timeIntervalSince(acquired) >= Self.staleAfter
    }
}

/// Errors surfaced when the lock cannot be acquired.
public enum SyncLockError: Error, Equatable, Sendable {
    /// A fresh (non-stale) lock owned by another device is already in place.
    /// `retryAfterSeconds` is a suggested back-off (30–60s in the iOS app).
    case heldByOtherDevice(holder: UUID, retryAfterSeconds: Int)
}
