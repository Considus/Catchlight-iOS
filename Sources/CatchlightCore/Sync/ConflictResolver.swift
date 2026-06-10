//
//  ConflictResolver.swift
//  CatchlightCore
//
//  Conflict DETECTION for the sync engine (Phase 5 brief §7.6). Resolution UI is
//  Phase 6 — this layer only decides what happened and never silently discards a
//  user's edit.
//
//  Catchlight v1.0 uses last-write timestamps plus the last-sync watermark rather
//  than vector clocks (a deliberate v1.0 simplification — full causal tracking is a
//  candidate for a later horizon). The rule, given a local and a remote version of
//  the same Take and the last-sync time:
//
//    • only the remote changed since last sync   → take remote
//    • only the local changed since last sync    → keep local (it will be pushed)
//    • BOTH changed and they differ              → CONFLICT (surface both to user)
//    • neither changed / identical               → no change
//
//  Because both versions decrypt with the same per-item key (same UUID → same HKDF
//  derivation) and every encryption uses a fresh random nonce, there is never a
//  nonce-collision risk when both versions are present (Encryption Architecture §11.2).
//

import Foundation

public enum SyncDecision: Equatable, Sendable {
    case noChange
    case takeRemote(Take)
    case keepLocal(Take)
    case conflict(local: Take, remote: Take)
}

public enum ConflictResolver {
    public static func decide(local: Take?, remote: Take, lastSync: Date?) -> SyncDecision {
        guard let local else {
            // Not present locally → a new Take created on another device.
            return .takeRemote(remote)
        }
        if local == remote { return .noChange }

        let watermark = lastSync ?? .distantPast
        let localChanged = local.modifiedAt > watermark
        let remoteChanged = remote.modifiedAt > watermark

        switch (localChanged, remoteChanged) {
        case (false, true):  return .takeRemote(remote)
        case (true, false):  return .keepLocal(local)
        case (true, true):   return .conflict(local: local, remote: remote)
        case (false, false):
            // Neither side recorded a change since last sync yet they differ —
            // the bookkeeping is confused (clock skew, watermark drift). The
            // previous fall-back silently overwrote by most-recent-write, which
            // violated this file's "never silently discards a user's edit"
            // contract. Surface it as a conflict instead (2026-06-10); the
            // existing resolution UI handles it at zero extra cost.
            return .conflict(local: local, remote: remote)
        }
    }
}
