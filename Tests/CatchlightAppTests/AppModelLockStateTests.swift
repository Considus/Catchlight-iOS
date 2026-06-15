//
//  AppModelLockStateTests.swift
//  CatchlightAppTests — D-042
//
//  Unit coverage for the app-entry lock-state machine on `AppModel`. The unlock
//  step is injected (`unlockKeys` / `makeStoreFromKeys`), so these tests exercise
//  the full transition graph WITHOUT touching the real Keychain or triggering a
//  Face ID / passcode prompt (which would hang a headless run). `attemptUnlock` is
//  async (the real Keychain retrieve runs off the main actor), so the tests await it.
//
//  The guarantee under test is the bug fix: a failed/cancelled unlock must NEVER
//  hand back a writable store — the app stays locked, and no data path opens.
//

#if canImport(Catchlight)
import XCTest
import Foundation
@testable import Catchlight
@testable import CatchlightCore

// A fixed, Sendable key for the injected `unlockKeys` (which runs off the main actor).
private func testUnlockKeys() throws -> KeyHierarchy {
    KeyHierarchy(masterKeyBytes: Data(repeating: 7, count: 32))
}

@MainActor
final class AppModelLockStateTests: XCTestCase {

    /// An onboarded user starting locked, with injectable unlock + store builder.
    private func makeLocked(
        unlockKeys: @escaping @Sendable () throws -> KeyHierarchy,
        makeStoreFromKeys: @escaping (KeyHierarchy) -> TakeStore?
    ) -> AppModel {
        AppModel(
            needsOnboarding: false,
            initialStore: InMemoryTakeStore(),     // the non-writable locked placeholder
            session: SessionController(),
            makeStoreFromKeys: makeStoreFromKeys,
            unlockKeys: unlockKeys,
            lockState: .locked,
            subscription: SubscriptionManager()
        )
    }

    func testUnlockSuccessBindsRealStoreAndUnlocks() async throws {
        let store = InMemoryTakeStore()
        try store.upsert(Take(blocks: [.textLine("hello")]))
        let app = makeLocked(unlockKeys: testUnlockKeys, makeStoreFromKeys: { _ in store })

        await app.attemptUnlock()

        XCTAssertEqual(app.lockState, .unlocked)
        XCTAssertEqual(try app.dailiesVM.store.allTakes().count, 1,
                       "timeline must bind to the unlocked store, not the empty placeholder")
    }

    func testUnlockAuthFailureStaysLockedAndBuildsNoStore() async {
        var builtStore = false
        let app = makeLocked(
            unlockKeys: { throw KeychainError.notFound },        // simulate cancel/fail
            makeStoreFromKeys: { _ in builtStore = true; return InMemoryTakeStore() }
        )

        await app.attemptUnlock()

        guard case .failed = app.lockState else {
            return XCTFail("auth failure must leave lockState == .failed")
        }
        XCTAssertFalse(builtStore, "no store may be built when the unlock fails")
    }

    func testUnlockUnopenableLibraryFailsAndSurfacesError() async {
        let app = makeLocked(unlockKeys: testUnlockKeys,
                             makeStoreFromKeys: { _ in nil })     // auth OK, DB won't open

        await app.attemptUnlock()

        guard case .failed = app.lockState else {
            return XCTFail("an unopenable library must leave lockState == .failed")
        }
        XCTAssertNotNil(app.lastSyncError, "the unopenable-library case surfaces the notice strip")
    }

    func testUnlockDoesNotSeed() async throws {
        let store = InMemoryTakeStore()                          // empty
        let app = makeLocked(unlockKeys: testUnlockKeys, makeStoreFromKeys: { _ in store })

        await app.attemptUnlock()

        XCTAssertEqual(app.lockState, .unlocked)
        XCTAssertEqual(try app.dailiesVM.store.allTakes().count, 0,
                       "seeding belongs to onboarding completion only — never a normal unlock")
    }

    func testRelockTearsDownStoreAndLocks() throws {
        let store = InMemoryTakeStore()
        try store.upsert(Take(blocks: [.textLine("secret")]))
        let app = AppModel(
            needsOnboarding: false,
            initialStore: store,
            session: SessionController(),
            makeStoreFromKeys: { _ in nil },
            unlockKeys: testUnlockKeys,
            lockState: .unlocked,
            subscription: SubscriptionManager()
        )
        XCTAssertEqual(try app.dailiesVM.store.allTakes().count, 1)

        app.relock()

        XCTAssertEqual(app.lockState, .locked)
        XCTAssertEqual(try app.dailiesVM.store.allTakes().count, 0,
                       "relock must tear the encrypted store down to an empty placeholder")
    }

    func testRelockNoOpDuringOnboarding() {
        let app = AppModel(
            needsOnboarding: true,
            initialStore: InMemoryTakeStore(),
            session: SessionController(),
            makeStoreFromKeys: { _ in nil },
            unlockKeys: testUnlockKeys,
            lockState: .unlocked,
            subscription: SubscriptionManager()
        )

        app.relock()

        XCTAssertEqual(app.lockState, .unlocked, "no key exists during onboarding — nothing to lock")
    }

    func testEnsureEntitledIsFalseWhileLockedWithNoSideEffects() {
        let app = makeLocked(unlockKeys: testUnlockKeys,
                             makeStoreFromKeys: { _ in InMemoryTakeStore() })

        XCTAssertFalse(app.ensureEntitled(), "mutations are refused while locked")
        XCTAssertFalse(app.ui.isPaywallPresented, "the lock guard must not present the paywall")
    }

    func testLockAfterSettingReadsDefaultsAndOverride() {
        let key = SettingsViewModel.LockAfter.defaultsKey
        let original = UserDefaults.standard.string(forKey: key)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(SettingsViewModel.LockAfter.current, .oneMinute, "default is 1 minute")

        UserDefaults.standard.set(SettingsViewModel.LockAfter.fiveMinutes.rawValue, forKey: key)
        XCTAssertEqual(SettingsViewModel.LockAfter.current, .fiveMinutes)
        XCTAssertEqual(SettingsViewModel.LockAfter.fiveMinutes.seconds, 300)
        XCTAssertEqual(SettingsViewModel.LockAfter.oneHour.seconds, 3600)
    }
}

@MainActor
final class SessionControllerLifecycleTests: XCTestCase {

    func testActiveClearsObscure() {
        let s = SessionController()
        s.handleScenePhase(.active)
        XCTAssertFalse(s.isObscured)
    }

    func testBackgroundObscuresAndDropsUnlock() {
        let s = SessionController()
        s.handleScenePhase(.background)
        XCTAssertTrue(s.isObscured)
        XCTAssertFalse(s.isUnlocked)
    }

    func testInactiveObscures() {
        // `.inactive` must obscure for the snapshot but deliberately does NOT tear
        // down keys (the Face ID-sheet relock-loop guard). We can't observe the
        // private key store headlessly; the structural guarantee is asserted by
        // code review + the device steps.
        let s = SessionController()
        s.handleScenePhase(.inactive)
        XCTAssertTrue(s.isObscured)
    }

    func testLockDropsKeys() {
        let s = SessionController()
        s.lock()
        XCTAssertFalse(s.isUnlocked)
        XCTAssertNil(s.currentKeys())
    }
}
#endif
