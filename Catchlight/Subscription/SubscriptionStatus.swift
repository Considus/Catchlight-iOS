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
        // A user who has never been entitled (post-onboarding pre-subscribe) is
        // in the same "must subscribe" lane as a lapsed subscriber — the UI
        // treats both identically (paywall on create/edit), so one terminal
        // state covers both rather than a fifth value. (The previous
        // `everSubscribed ? .lapsed : .lapsed` ternary said this confusingly.)
        return .lapsed
    }
}

/// One Annual subscription transaction (a purchase or a renewal) as the diagnostics log
/// shows it. StoreKit-free so the line can be unit-tested; built from a `Transaction` by
/// `SubscriptionManager.historyEntry(_:)`. Carries no transaction id or anything else that
/// identifies the person.
struct SubscriptionHistoryEntry: Equatable {
    let purchased: Date
    let expires: Date?
    /// "introductory", "promotional", "code", "win-back", or nil for a full-price period.
    let offerType: String?
    /// The offer's id (an offer code's or promotional offer's reference); nil for the intro offer.
    let offerID: String?
    /// "free trial", "pay as you go" or "pay up front".
    let paymentMode: String?
    let price: Decimal?
    let currency: String?
    let environment: String
    let revoked: Bool

    /// "<start> to <end>, offer <type> (<id>, <mode>), price <amount> <currency>, <store>".
    var summary: String {
        let period = "\(Self.stamp(purchased)) to \(expires.map(Self.stamp) ?? "no expiry")"
        let offer = offerType.map { "offer \($0) (\(offerID ?? "no id"), \(paymentMode ?? "unknown payment"))" } ?? "no offer"
        let amount = ["price", price.map { "\($0)" } ?? "unknown", currency]
            .compactMap { $0 }.joined(separator: " ")
        return [period, offer, amount, environment, revoked ? "revoked" : nil]
            .compactMap { $0 }.joined(separator: ", ")
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter.string(from: date)
    }
}
