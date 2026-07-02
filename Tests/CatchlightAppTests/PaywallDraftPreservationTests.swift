//
//  PaywallDraftPreservationTests.swift
//  CatchlightAppTests — 2026-07-01 mid-point review remediation (owner decision)
//
//  A typed draft whose save is interrupted by the paywall is HELD, not
//  destroyed: saved if the user subscribes while the paywall is up, dropped if
//  the paywall closes without an active subscription. Previously all three
//  interrupted save paths (locked capture, timeline inline edit, Storyboard
//  edit) silently discarded the text the moment the paywall appeared.
//
//  Also first coverage for the CaptureRouting App-Group hand-off (URL
//  round-trip and set/read/clear), flagged untested in the review.
//
//  iOS-only — gated on `canImport(Catchlight)`. Uses the DEBUG-only
//  `forceStatusForTesting` seam; test builds are always Debug.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight
@testable import CatchlightCore

private func testUnlockKeys() throws -> KeyHierarchy {
    KeyHierarchy(masterKeyBytes: Data(repeating: 7, count: 32))
}

@MainActor
final class PaywallDraftPreservationTests: XCTestCase {

    /// An unlocked, onboarded AppModel over an in-memory store, with the
    /// subscription pinned to `status`.
    private func makeUnlocked(status: SubscriptionStatus) async -> (AppModel, InMemoryTakeStore) {
        let store = InMemoryTakeStore()
        let subscription = SubscriptionManager()
        subscription.forceStatusForTesting(status)
        let app = AppModel(
            needsOnboarding: false,
            initialStore: InMemoryTakeStore(),
            session: SessionController(),
            makeStoreFromKeys: { _ in store },
            unlockKeys: testUnlockKeys,
            lockState: .locked,
            subscription: subscription
        )
        await app.attemptUnlock()
        XCTAssertEqual(app.lockState, .unlocked)
        return (app, store)
    }

    func testHeldDraft_savedOnPaywallDismiss_whenSubscribed() async throws {
        let (app, store) = await makeUnlocked(status: .lapsed)
        let draft = Take(blocks: [.textLine("typed at the paywall")])

        XCTAssertFalse(app.ensureEntitled(), "a lapsed user must hit the paywall")
        app.holdDraftForPaywall(draft)
        XCTAssertTrue(try store.allTakes().isEmpty, "nothing may be written while held")

        // The user subscribes from the paywall, then it dismisses.
        app.subscription.forceStatusForTesting(.subscribed)
        app.resolvePendingEntitledSave()

        XCTAssertEqual(try store.allTakes().map(\.id), [draft.id],
                       "the held draft must be saved once entitled")
        XCTAssertNil(app.pendingEntitledSave)
    }

    func testHeldDraft_droppedOnPaywallDismiss_whenStillLapsed() async throws {
        let (app, store) = await makeUnlocked(status: .lapsed)
        app.holdDraftForPaywall(Take(blocks: [.textLine("never subscribed")]))

        app.resolvePendingEntitledSave()   // paywall closed, still lapsed

        XCTAssertTrue(try store.allTakes().isEmpty,
                      "no subscription → the held draft is dropped, not written")
        XCTAssertNil(app.pendingEntitledSave)
    }

    func testResolveWithNothingHeld_isANoOp() async throws {
        let (app, store) = await makeUnlocked(status: .subscribed)
        app.resolvePendingEntitledSave()
        XCTAssertTrue(try store.allTakes().isEmpty)
    }

    // MARK: - CaptureRouting hand-off (first coverage)

    func testCaptureURL_roundTripsEveryMode() {
        for mode in CaptureRouting.Mode.allCases {
            XCTAssertEqual(CaptureRouting.mode(from: CaptureRouting.captureURL(mode)), mode)
        }
    }

    func testPending_setReadClear_roundTrips() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: AppGroup.identifier))
        defer { CaptureRouting.clearPending(defaults: defaults) }

        let pending = CaptureRouting.Pending(mode: .obie, text: "dictated text")
        CaptureRouting.setPending(pending, defaults: defaults)
        XCTAssertEqual(CaptureRouting.pending(defaults: defaults), pending)

        CaptureRouting.clearPending(defaults: defaults)
        XCTAssertNil(CaptureRouting.pending(defaults: defaults))
    }

    func testPending_launcherWithoutText_readsBackNilText() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: AppGroup.identifier))
        defer { CaptureRouting.clearPending(defaults: defaults) }

        CaptureRouting.setPending(.init(mode: .text), defaults: defaults)
        let read = try XCTUnwrap(CaptureRouting.pending(defaults: defaults))
        XCTAssertEqual(read.mode, .text)
        XCTAssertNil(read.text)
    }
}
#endif
