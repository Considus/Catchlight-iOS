//
//  SubscriptionStatus.swift
//  Catchlight (iOS app target) — Task 6.21
//
//  Pure types for the subscription state machine. Kept free of StoreKit so the
//  derivation can be unit-tested without spinning up a sandbox: callers convert
//  a real `StoreKit.Transaction` into an `EntitlementSnapshot` and feed those
//  into `SubscriptionStatus.derive(from:everSubscribed:)`.
//

import Foundation

/// The four states the UI cares about. `.unknown` is the launch resting state
/// until the first entitlement check completes; the app treats `.unknown` as
/// "do not block" (no paywall) so a cold launch never flashes the gate.
enum SubscriptionStatus: String, Equatable, CaseIterable {
    case unknown
    case trial
    case subscribed
    case lapsed

    /// True when the user can create / edit Takes. `.unknown` is permissive so
    /// the entitlement check race at launch never punishes a paying user.
    var isEntitled: Bool {
        switch self {
        case .trial, .subscribed, .unknown: return true
        case .lapsed: return false
        }
    }
}

/// StoreKit-free representation of one current entitlement. Constructed by
/// `SubscriptionManager` from a verified `Transaction`.
struct EntitlementSnapshot: Equatable {
    let productID: String
    /// `true` when this transaction was purchased via the introductory offer
    /// (i.e. the user is currently in their free-trial window).
    let isInTrial: Bool
    /// `true` when the transaction is currently active (not revoked, not expired).
    let isActive: Bool
}

extension SubscriptionStatus {
    /// Pure derivation of the user-visible status from a set of current
    /// entitlement snapshots plus the persisted "has ever been entitled" flag.
    /// Lapsed = previously seen an entitlement, none active right now.
    static func derive(from snapshots: [EntitlementSnapshot],
                       everSubscribed: Bool) -> SubscriptionStatus {
        let active = snapshots.first { $0.isActive }
        if let active {
            return active.isInTrial ? .trial : .subscribed
        }
        return everSubscribed ? .lapsed : .lapsed
        // NOTE: a user who has never been entitled (post-onboarding pre-subscribe)
        // is still in the "must subscribe" lane — the UI treats this identically
        // to lapsed (paywall surfaces on create/edit). We keep one terminal state
        // for both rather than introducing a fifth value.
    }
}
