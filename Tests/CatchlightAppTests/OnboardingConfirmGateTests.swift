//
//  OnboardingConfirmGateTests.swift
//  CatchlightTests
//
//  The confirm gate's selection model — V7 (audit 2026-08, D-228): a filled slot
//  deselects on tap. This screen guards the recovery phrase, so the behaviour is
//  proved here rather than eyeballed: a word that leaves a slot must return to
//  the bank, and the gate must still pass after a mistake is corrected.
//

import XCTest
@testable import Catchlight

@MainActor
final class OnboardingConfirmGateTests: XCTestCase {

    /// A VM driven to the confirm step through the real flow (cloud path — no
    /// local-warning detour). The mnemonic and bank are freshly generated per
    /// test; every assertion works from the VM's own published state.
    private func makeConfirmVM() -> OnboardingViewModel {
        let vm = OnboardingViewModel(onComplete: { _, _ in })
        vm.beginStorageChoice()
        vm.chooseStorage(.cloud)
        vm.proceedToConfirm()
        return vm
    }

    /// The three words the gate expects, in slot order.
    private func expectedWords(_ vm: OnboardingViewModel) -> [String] {
        vm.targetPositions.map { vm.mnemonic[$0] }
    }

    // MARK: - The deselect (D-228)

    func testDeselect_returnsTheWordToTheBank() {
        let vm = makeConfirmVM()
        vm.tapBankWord(at: 0)
        XCTAssertEqual(vm.slots[0], vm.bank[0])
        XCTAssertTrue(vm.usedBankIndices.contains(0))

        vm.deselectSlot(at: 0)
        XCTAssertEqual(vm.slots, [nil, nil, nil], "the slot must empty")
        XCTAssertTrue(vm.usedBankIndices.isEmpty,
                      "the word must return to the pool — a vanished word makes the gate unwinnable")

        // And the freed tile is genuinely usable again.
        vm.tapBankWord(at: 0)
        XCTAssertEqual(vm.slots[0], vm.bank[0])
    }

    func testDeselect_freedSlotIsTheNextToFill() {
        let vm = makeConfirmVM()
        vm.tapBankWord(at: 0)
        vm.tapBankWord(at: 1)
        vm.deselectSlot(at: 0)

        XCTAssertEqual(vm.nextSlotIndex, 0, "the hole refills in place")
        XCTAssertEqual(vm.slots[1], vm.bank[1], "the untouched slot keeps its word")

        vm.tapBankWord(at: 2)
        XCTAssertEqual(vm.slots[0], vm.bank[2])
        XCTAssertEqual(vm.slots[1], vm.bank[1])
    }

    func testDeselect_emptySlotIsANoOp() {
        let vm = makeConfirmVM()
        vm.deselectSlot(at: 1)
        XCTAssertEqual(vm.slots, [nil, nil, nil])
        XCTAssertTrue(vm.usedBankIndices.isEmpty)
        XCTAssertFalse(vm.flashError)
    }

    func testDeselect_neverTriggersValidation() {
        // Validation runs only when the third slot FILLS; leaving a slot must not
        // re-run it, flash an error, or advance the step.
        let vm = makeConfirmVM()
        vm.tapBankWord(at: 0)
        vm.tapBankWord(at: 1)
        vm.deselectSlot(at: 1)
        XCTAssertFalse(vm.flashError)
        XCTAssertEqual(vm.step, .confirm)
    }

    func testDeselect_ignoredWhileTheErrorFlashResets() {
        // Three wrong words: the expected words placed out of order (distinct by
        // generation, so a swapped order is guaranteed wrong). The row is locked
        // while it flashes and auto-resets; a deselect in that window must not
        // fight the reset.
        let vm = makeConfirmVM()
        let expected = expectedWords(vm)
        vm.tapBankWord(expected[1])
        vm.tapBankWord(expected[0])
        vm.tapBankWord(expected[2])
        XCTAssertTrue(vm.flashError, "out-of-order placement must fail the gate")

        let frozen = vm.slots
        vm.deselectSlot(at: 0)
        XCTAssertEqual(vm.slots, frozen, "locked during the flash, as the bank tiles are")
    }

    // MARK: - The headline: a corrected mistake still passes the gate

    func testMisplacedWordCorrectedByDeselect_stillCompletes() {
        let vm = makeConfirmVM()
        let expected = expectedWords(vm)

        // Mis-place: a word that is NOT the first expected word.
        let wrongIndex = vm.bank.indices.first { vm.bank[$0] != expected[0] }!
        vm.tapBankWord(at: wrongIndex)
        XCTAssertEqual(vm.slots[0], vm.bank[wrongIndex])

        // Recover in place, then answer correctly.
        vm.deselectSlot(at: 0)
        for word in expected { vm.tapBankWord(word) }
        XCTAssertEqual(vm.step, .complete,
                       "the gate must pass after a deselect-corrected mistake")
    }
}
