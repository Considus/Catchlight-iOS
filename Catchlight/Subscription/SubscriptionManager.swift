//
//  SubscriptionManager.swift
//  Catchlight (iOS app target) — Tasks 6.20 / 6.21
//
//  StoreKit 2 subscription state for Catchlight Annual. Single product,
//  single subscription group. The manager is the only thing in the app that
//  talks to StoreKit; AppModel reads the resulting `status` and the paywall
//  view drives `purchase()` / `restore()` / `redeem()`.
//
//  Status derivation is delegated to `SubscriptionStatus.derive(from:…)`,
//  which is a pure function over `EntitlementSnapshot` — unit-testable without
//  any StoreKit harness (see SubscriptionStatusTests).
//

import Foundation
import StoreKit
import Observation
import CatchlightCore

@Observable
@MainActor
final class SubscriptionManager {

    /// Production product identifier — also the identifier inside
    /// `Catchlight.storekit` for local sandbox testing.
    static let annualProductID = "com.considus.catchlight.annual"

    /// User-visible state. Starts `.unknown`; flips after the first call to
    /// `refreshEntitlements()`. AppModel reads this.
    private(set) var status: SubscriptionStatus = .unknown

    /// The Annual product, resolved lazily from the App Store. Nil before the
    /// first `loadProduct()` succeeds. The paywall renders price + trial
    /// language directly off this object so a price change in App Store
    /// Connect is reflected without an app update.
    private(set) var annual: Product?

    /// True while an interactive purchase / restore is in flight; the paywall
    /// disables its CTAs to prevent double-taps.
    private(set) var isWorking = false

    /// User-visible error string surfaced under the CTA. Cleared on next action.
    private(set) var lastError: String?

    private let defaults: UserDefaults
    /// Persistent "has this install ever been entitled" flag (app-group defaults).
    /// Exposed (non-private) so the DEBUG reset can clear it as part of a
    /// fresh-install wipe (DebugReset). Production code only reads/writes it here.
    static let everEntitledDefaultsKey = "catchlight.subscription.everEntitled"

    // `nonisolated(unsafe)`: deinit is nonisolated and may not touch
    // MainActor-isolated state under the current toolchain; access is confined
    // to startObservingUpdates (MainActor) + cancel-on-deinit, which is safe.
    nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

    /// Task 6.19 — Spotlight indexer attached by AppModel. The manager is
    /// constructable before AppModel exists (Wiring builds it first, then
    /// hands it to AppModel which calls `attachSpotlightIndexer`). On every
    /// lapse transition the manager calls `deindexAll()` so a lapsed user's
    /// Takes can't be discovered via system search.
    private var spotlight: SpotlightIndexing?

    /// Inject the indexer post-construction. Idempotent — calling twice
    /// replaces the previous reference.
    func attachSpotlightIndexer(_ indexer: SpotlightIndexing) {
        self.spotlight = indexer
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Begin observing real-time transaction changes. Idempotent — safe to call
    /// multiple times; only the first call installs the listener.
    func startObservingUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
    }

    /// Fetch the annual product metadata from the App Store (cached). The
    /// paywall calls this on appear; safe to call repeatedly.
    func loadProduct() async {
        if annual != nil { return }
        do {
            let products = try await Product.products(for: [Self.annualProductID])
            annual = products.first
            // `isEligibleForIntroOffer` is an async StoreKit property on the
            // current SDK — resolve it once here and cache, so the paywall's
            // synchronous view code can read it.
            introOfferEligible = await annual?.subscription?.isEligibleForIntroOffer ?? false
        } catch {
            lastError = "Couldn't reach the App Store. Check your connection."
        }
    }

    /// Cached at `loadProduct()` time (the underlying StoreKit property is async).
    private(set) var introOfferEligible = false

    /// Walk `Transaction.currentEntitlements` and update `status`. Called on
    /// launch, on scenePhase → active, and after every purchase / restore.
    func refreshEntitlements() async {
        #if DEBUG
        // A status forced by `forceStatusForTesting` is authoritative for the
        // whole run. Without this guard, the unconditional launch refresh walked
        // the (empty) real entitlements and overwrote the forced `.subscribed`
        // with `.lapsed` — so every "entitled" UI-test flow actually ran
        // paywalled, silently defeating the test hook.
        if statusIsForcedForTesting { return }
        #endif
        var snapshots: [EntitlementSnapshot] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let txn) = result else { continue }
            guard txn.productID == Self.annualProductID else { continue }
            snapshots.append(EntitlementSnapshot(
                productID: txn.productID,
                isInTrial: txn.offerType == .introductory,
                isActive: txn.revocationDate == nil
                    && (txn.expirationDate.map { $0 > Date() } ?? true)
            ))
        }
        let ever = defaults.bool(forKey: Self.everEntitledDefaultsKey)
        let derived = SubscriptionStatus.derive(from: snapshots, everSubscribed: ever)
        // Persist "has ever been entitled" the first time we see an active
        // transaction, so a later expiry resolves to `.lapsed` rather than
        // the initial-purchase prompt.
        if snapshots.contains(where: { $0.isActive }) && !ever {
            defaults.set(true, forKey: Self.everEntitledDefaultsKey)
        }
        let previous = status
        status = derived
        // Task 6.19 — belt and braces: on entering `.lapsed` (from any other
        // state), wipe the OS Spotlight index of every Take. Re-indexing on
        // resubscribe happens organically on the next save; we deliberately
        // don't try to re-index in bulk here since the manager doesn't hold
        // the store.
        if derived == .lapsed && previous != .lapsed {
            spotlight?.deindexAll()
        }
    }

    /// Initiate the in-app purchase flow against the bound scene. Returns true
    /// when the user successfully subscribed (the paywall dismisses on true).
    @discardableResult
    func purchase() async -> Bool {
        guard let annual else {
            lastError = "Subscription is unavailable right now."
            return false
        }
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        do {
            let result = try await annual.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let txn) = verification {
                    await txn.finish()
                }
                await refreshEntitlements()
                return status.isEntitled && status != .unknown
            case .pending:
                // Ask to Buy / SCA: the purchase is awaiting approval. Surface
                // it — previously this returned false with no message, so the
                // button just stopped spinning and nothing else happened.
                lastError = "Your purchase is awaiting approval. You'll get access as soon as it's confirmed."
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = "Purchase couldn't complete. Please try again."
            return false
        }
    }

    /// Apple-required restore flow — forces a sync with the App Store and
    /// re-checks entitlements. Returns true when the restore produced an
    /// active entitlement so the paywall can dismiss and confirm success
    /// (previously the sheet stayed open with no feedback either way).
    @discardableResult
    func restore() async -> Bool {
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if status.isEntitled { return true }
            lastError = "No active subscription was found for this Apple ID."
            return false
        } catch {
            lastError = "Couldn't restore purchases. Please try again."
            return false
        }
    }

    /// Pricing copy for the CTA. Uses StoreKit's locale-aware display price.
    var ctaPriceCopy: String {
        guard let annual else { return "" }
        return "\(annual.displayPrice)/year"
    }

    #if DEBUG
    /// Test-only escape hatch — UI tests set a deterministic status without
    /// touching StoreKit. Compiled out of Release builds. Once forced, the
    /// status is pinned: `refreshEntitlements()` becomes a no-op for the run.
    private var statusIsForcedForTesting = false
    func forceStatusForTesting(_ value: SubscriptionStatus) {
        statusIsForcedForTesting = true
        status = value
    }
    #endif

    /// Trial-eligible callers see the trial CTA; otherwise the plain subscribe one.
    var isEligibleForIntroOffer: Bool { introOfferEligible }

    /// Human-readable trial length, e.g. "14 days" — pulled live from the
    /// product's intro offer rather than hard-coded.
    var trialDurationCopy: String? {
        guard let offer = annual?.subscription?.introductoryOffer else { return nil }
        let n = offer.period.value
        switch offer.period.unit {
        case .day: return "\(n) day\(n == 1 ? "" : "s")"
        case .week: return "\(n) week\(n == 1 ? "" : "s")"
        case .month: return "\(n) month\(n == 1 ? "" : "s")"
        case .year: return "\(n) year\(n == 1 ? "" : "s")"
        @unknown default: return nil
        }
    }

    /// Adjectival (hyphenated, singular-unit) trial length, e.g. "14-day" —
    /// for copy like "Start your 14-day free trial" (owner-locked CTA,
    /// HiFi v1.11.1). Same live intro-offer source as `trialDurationCopy`.
    var trialDurationAdjectiveCopy: String? {
        guard let offer = annual?.subscription?.introductoryOffer else { return nil }
        let n = offer.period.value
        switch offer.period.unit {
        case .day: return "\(n)-day"
        case .week: return "\(n)-week"
        case .month: return "\(n)-month"
        case .year: return "\(n)-year"
        @unknown default: return nil
        }
    }
}
