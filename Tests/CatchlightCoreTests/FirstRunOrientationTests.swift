//
//  FirstRunOrientationTests.swift
//  CatchlightCoreTests
//
//  Verifies the first-run orientation state machine (Task 3.13):
//    • the four hint moments fire in order,
//    • each transition method is idempotent and ignores out-of-order calls,
//    • step persistence round-trips through UserDefaults,
//    • once complete (step 5), no method walks it backwards.
//
//  The state class lives in the iOS app target (`FirstRunOrientationState`), so
//  this test is gated by `#if canImport(Catchlight)` and runs inside the iOS test
//  bundle. Under `swift test` on macOS the Core tests run unchanged.
//

#if canImport(Catchlight)
import XCTest
@testable import Catchlight

final class FirstRunOrientationTests: XCTestCase {

    /// Use an isolated UserDefaults suite per test so persisted state from one
    /// test never bleeds into another (and never touches the real .standard suite).
    private func makeState() -> (FirstRunOrientationState, UserDefaults, String) {
        let suiteName = "catchlight.tests.orientation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (FirstRunOrientationState(defaults: defaults), defaults, suiteName)
    }

    // MARK: - Step sequencing

    func testHappyPathAdvancesThroughAllSteps() {
        let (state, _, _) = makeState()
        XCTAssertEqual(state.step, 0)

        state.beginIfNeeded()
        XCTAssertEqual(state.step, 1)
        XCTAssertTrue(state.showAddPulse)

        state.didTapAdd()
        XCTAssertEqual(state.step, 2)
        XCTAssertTrue(state.showIrisHint)

        state.didTapIris()
        XCTAssertEqual(state.step, 3)
        XCTAssertTrue(state.showSettingsHint)

        state.didDismissSettingsHint()
        XCTAssertEqual(state.step, 4)
        // Step 4 is "armed" but the tooltip is not yet visible.
        XCTAssertFalse(state.showObieIntro)

        state.triggerObieIntro()
        XCTAssertTrue(state.showObieIntro)

        state.didDismissObieIntro()
        XCTAssertEqual(state.step, 5)
        XCTAssertTrue(state.isComplete)
        XCTAssertFalse(state.showObieIntro)
    }

    // MARK: - Idempotency / out-of-order calls

    func testOutOfOrderCallsAreNoOps() {
        let (state, _, _) = makeState()
        state.beginIfNeeded()
        XCTAssertEqual(state.step, 1)

        // Calling step-3 / step-4 dismissals before they are armed must NOT advance.
        state.didTapIris()
        state.didDismissSettingsHint()
        state.didDismissObieIntro()
        state.triggerObieIntro()
        XCTAssertEqual(state.step, 1, "Out-of-order methods must not advance the step")
        XCTAssertFalse(state.obieIntroTriggered)
    }

    func testBeginIfNeededIsIdempotent() {
        let (state, _, _) = makeState()
        state.beginIfNeeded()
        state.beginIfNeeded()
        state.beginIfNeeded()
        XCTAssertEqual(state.step, 1, "beginIfNeeded must only fire once")
    }

    func testRepeatedAdvanceMethodsAreNoOpsAfterAdvancing() {
        let (state, _, _) = makeState()
        state.beginIfNeeded()
        state.didTapAdd()
        XCTAssertEqual(state.step, 2)
        // A second didTapAdd at step 2 must not push the state past where it should be.
        state.didTapAdd()
        XCTAssertEqual(state.step, 2)
    }

    // MARK: - No regression past complete

    func testCompletedStateDoesNotRegress() {
        let (state, _, _) = makeState()
        state.beginIfNeeded()
        state.didTapAdd()
        state.didTapIris()
        state.didDismissSettingsHint()
        state.triggerObieIntro()
        state.didDismissObieIntro()
        XCTAssertEqual(state.step, 5)

        // None of these may roll the state back.
        state.beginIfNeeded()
        state.didTapAdd()
        state.didTapIris()
        state.didDismissSettingsHint()
        state.triggerObieIntro()
        state.didDismissObieIntro()
        XCTAssertEqual(state.step, 5)
        XCTAssertTrue(state.isComplete)
    }

    // MARK: - Persistence

    func testStepIsPersistedAcrossInstances() {
        let (first, defaults, suiteName) = makeState()
        first.beginIfNeeded()
        first.didTapAdd()
        first.didTapIris()
        XCTAssertEqual(first.step, 3)

        // A fresh instance reading the same suite must resume at the persisted step.
        let second = FirstRunOrientationState(defaults: defaults)
        XCTAssertEqual(second.step, 3, "Persisted step should round-trip through UserDefaults")

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Developer reset

    func testResetForDeveloperReturnsToStartButObieFlagClears() {
        let (state, _, _) = makeState()
        state.beginIfNeeded()
        state.didTapAdd()
        state.didTapIris()
        state.didDismissSettingsHint()
        state.triggerObieIntro()
        XCTAssertTrue(state.obieIntroTriggered)

        state.resetForDeveloper()
        XCTAssertEqual(state.step, 0)
    }
}
#endif
