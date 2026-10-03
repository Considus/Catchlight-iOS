//
//  SubscriptionStatusTests.swift
//  CatchlightCoreTests — Tasks 6.20 / 6.21
//
//  Pure derivation of SubscriptionStatus from entitlement snapshots, plus the
//  AppModel-level gating helper (`ensureEntitled`) that opens the paywall when
//  the user is unentitled. StoreKit itself is not exercised here — it would
//  require a sandbox tester account; the pure-function seam means we don't
//  need one. Lives in the iOS test bundle since the types are app-target.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight
@testable import CatchlightCore

final class SubscriptionStatusTests: XCTestCase {

    private func snap(active: Bool, trial: Bool) -> EntitlementSnapshot {
        EntitlementSnapshot(productID: SubscriptionManager.annualProductID,
                            isInTrial: trial,
                            isActive: active)
    }

    // MARK: - Pure derivation

    func testDerive_noSnapshotsNeverSubscribed_isLapsed() {
        // First-launch / post-onboarding pre-purchase. The UI surfaces the
        // paywall — same lane as a lapsed user.
        let status = SubscriptionStatus.derive(from: [], everSubscribed: false)
        XCTAssertEqual(status, .lapsed)
    }

    func testDerive_noSnapshotsAfterEverSubscribed_isLapsed() {
        let status = SubscriptionStatus.derive(from: [], everSubscribed: true)
        XCTAssertEqual(status, .lapsed)
    }

    func testDerive_activeTrialSnapshot_isTrial() {
        let status = SubscriptionStatus.derive(
            from: [snap(active: true, trial: true)],
            everSubscribed: false)
        XCTAssertEqual(status, .trial)
    }

    func testDerive_activeSubscriptionSnapshot_isSubscribed() {
        let status = SubscriptionStatus.derive(
            from: [snap(active: true, trial: false)],
            everSubscribed: true)
        XCTAssertEqual(status, .subscribed)
    }

    func testDerive_onlyInactiveSnapshots_isLapsed() {
        let status = SubscriptionStatus.derive(
            from: [snap(active: false, trial: false)],
            everSubscribed: true)
        XCTAssertEqual(status, .lapsed)
    }

    func testDerive_mixedActiveAndInactive_prefersActive() {
        let status = SubscriptionStatus.derive(
            from: [snap(active: false, trial: false),
                   snap(active: true, trial: true)],
            everSubscribed: true)
        XCTAssertEqual(status, .trial)
    }

    // MARK: - Entitlement bool

    func testIsEntitled_unknownIsPermissive() {
        // Cold-launch race must not block paying users.
        XCTAssertTrue(SubscriptionStatus.unknown.isEntitled)
    }

    func testIsEntitled_trialAndSubscribedAreEntitled() {
        XCTAssertTrue(SubscriptionStatus.trial.isEntitled)
        XCTAssertTrue(SubscriptionStatus.subscribed.isEntitled)
    }

    func testIsEntitled_lapsedIsNot() {
        XCTAssertFalse(SubscriptionStatus.lapsed.isEntitled)
    }

    // MARK: - AppModel gating

    @MainActor
    func testEnsureEntitled_whenLapsed_opensPaywallAndReturnsFalse() {
        let manager = SubscriptionManager(defaults: isolatedDefaults())
        manager.forceStatusForTesting(.lapsed)
        let app = AppModel(needsOnboarding: false,
                           initialStore: InMemoryTakeStore(),
                           session: SessionController(),
                           makeStoreFromKeys: { _ in nil },
                           unlockKeys: { throw KeychainError.notFound },
                           subscription: manager)

        XCTAssertFalse(app.ui.isPaywallPresented)
        let permitted = app.ensureEntitled()
        XCTAssertFalse(permitted)
        XCTAssertTrue(app.ui.isPaywallPresented)
    }

    @MainActor
    func testEnsureEntitled_whenSubscribed_returnsTrueAndDoesNotShowPaywall() {
        let manager = SubscriptionManager(defaults: isolatedDefaults())
        manager.forceStatusForTesting(.subscribed)
        let app = AppModel(needsOnboarding: false,
                           initialStore: InMemoryTakeStore(),
                           session: SessionController(),
                           makeStoreFromKeys: { _ in nil },
                           unlockKeys: { throw KeychainError.notFound },
                           subscription: manager)

        let permitted = app.ensureEntitled()
        XCTAssertTrue(permitted)
        XCTAssertFalse(app.ui.isPaywallPresented)
    }

    @MainActor
    func testEnsureEntitled_whenTrial_returnsTrue() {
        let manager = SubscriptionManager(defaults: isolatedDefaults())
        manager.forceStatusForTesting(.trial)
        let app = AppModel(needsOnboarding: false,
                           initialStore: InMemoryTakeStore(),
                           session: SessionController(),
                           makeStoreFromKeys: { _ in nil },
                           unlockKeys: { throw KeychainError.notFound },
                           subscription: manager)

        XCTAssertTrue(app.ensureEntitled())
        XCTAssertFalse(app.ui.isPaywallPresented)
    }

    @MainActor
    func testPresentPaywallIfNeededAfterOnboarding_unentitled_opensPaywall() {
        let manager = SubscriptionManager(defaults: isolatedDefaults())
        manager.forceStatusForTesting(.lapsed)
        let app = AppModel(needsOnboarding: false,
                           initialStore: InMemoryTakeStore(),
                           session: SessionController(),
                           makeStoreFromKeys: { _ in nil },
                           unlockKeys: { throw KeychainError.notFound },
                           subscription: manager)
        app.presentPaywallIfNeededAfterOnboarding()
        XCTAssertTrue(app.ui.isPaywallPresented)
    }

    @MainActor
    func testPresentPaywallIfNeededAfterOnboarding_subscribed_doesNotOpen() {
        let manager = SubscriptionManager(defaults: isolatedDefaults())
        manager.forceStatusForTesting(.subscribed)
        let app = AppModel(needsOnboarding: false,
                           initialStore: InMemoryTakeStore(),
                           session: SessionController(),
                           makeStoreFromKeys: { _ in nil },
                           unlockKeys: { throw KeychainError.notFound },
                           subscription: manager)
        app.presentPaywallIfNeededAfterOnboarding()
        XCTAssertFalse(app.ui.isPaywallPresented)
    }

    @MainActor
    func testPresentPaywallIfNeededAfterOnboarding_stillOnboarding_isNoOp() {
        let manager = SubscriptionManager(defaults: isolatedDefaults())
        manager.forceStatusForTesting(.lapsed)
        let app = AppModel(needsOnboarding: true,
                           initialStore: InMemoryTakeStore(),
                           session: SessionController(),
                           makeStoreFromKeys: { _ in nil },
                           unlockKeys: { throw KeychainError.notFound },
                           subscription: manager)
        app.presentPaywallIfNeededAfterOnboarding()
        XCTAssertFalse(app.ui.isPaywallPresented)
    }

    // MARK: - Helpers

    /// Per-test ephemeral UserDefaults so the persisted "everSubscribed" flag
    /// never bleeds between cases or into the real defaults database.
    private func isolatedDefaults() -> UserDefaults {
        let name = "catchlight.tests.subscription.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
}
#endif
