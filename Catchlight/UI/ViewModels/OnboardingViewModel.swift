//
//  OnboardingViewModel.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  Owns first-launch onboarding (UX Session Decisions v2.5 §15, six screens):
//    1. welcome         — calm framing + "privacy phrase" intro
//    2. storageChoice   — local-only vs cloud-backed (user choice, branches flow)
//    3. localWarning    — shown only on the local path
//    4. reveal          — the 12-word privacy phrase
//    5. confirm         — free-selection: tap 3 target words from the bank
//    6. complete        — "You're ready." → tap to derive + store master key
//    Plus `.failure` — Keychain or derivation failure with a Start-over escape hatch.
//
//  WORDLIST: the bundled official 2048-word list is loaded by
//  `EnglishWordlist.load()` and verified against a pinned SHA-256 on every start.
//  A missing or corrupt resource is a fatal build error — recovery across clients
//  depends on byte-identical wordlists, so we refuse to proceed with anything else.
//

import Foundation
import Observation
import CryptoKit
import CatchlightCore

@Observable
final class OnboardingViewModel {

    enum Step {
        case welcome
        case restoreEntry     // "I already use Catchlight" — enter an existing phrase
        case storageChoice
        case localWarning
        case reveal
        case confirm
        case complete
        case failure
    }

    enum StoragePath {
        case local
        case cloud
    }

    private(set) var step: Step = .welcome

    /// The user's storage choice. Set on Screen 2; controls the local-warning
    /// branch and varies the copy on Screens 4 and 6.
    private(set) var storagePath: StoragePath = .local

    /// The generated 12-word mnemonic ("privacy phrase").
    private(set) var mnemonic: [String] = []

    // MARK: - Confirm (free-selection model — Pass 1, unchanged)

    private(set) var targetPositions: [Int] = []
    private(set) var bank: [String] = []
    private(set) var slots: [String?] = [nil, nil, nil]
    /// Bank-tile usage is tracked BY INDEX, not by word value (2026-06-10).
    /// ~3% of BIP-39 phrases legitimately contain a duplicate word; tracking by
    /// string greyed both copies on one tap and made the confirm step
    /// unwinnable when a duplicated word was required twice — with no escape on
    /// that screen. (Generation now also avoids duplicate-word phrases, so this
    /// is defence in depth.)
    private(set) var usedBankIndices: Set<Int> = []
    private(set) var flashError: Bool = false

    private(set) var failure: String?
    private(set) var failureDetail: String?

    private let bip39: BIP39
    /// Carries the just-derived 32-byte master key so the app can open the store
    /// directly (no Keychain read, hence no Face ID/passcode prompt right after
    /// onboarding). D-042. The `isRestore` flag distinguishes a fresh generate
    /// (seed the starter Takes) from a cross-device restore (skip seeding — the
    /// real Takes arrive from the cloud folder, and seeding here would push five
    /// example Takes UP into the user's real data on first sync). D-103.
    private let onComplete: (Data, _ isRestore: Bool) -> Void

    init(onComplete: @escaping (Data, _ isRestore: Bool) -> Void) {
        self.onComplete = onComplete
        do {
            self.bip39 = BIP39(wordlist: try EnglishWordlist.load())
        } catch {
            fatalError("BIP-39 wordlist missing or corrupt: \(error)")
        }
    }

    // MARK: - Flow

    /// Screen 1 → Screen 2.
    func beginStorageChoice() { step = .storageChoice }

    /// Screen 2 → Screen 3 (local) or Screen 4 (cloud).
    func chooseStorage(_ path: StoragePath) {
        storagePath = path
        switch path {
        case .local: step = .localWarning
        case .cloud: revealPhrase()
        }
    }

    /// Screen 3 secondary action — go back to storage choice.
    func backToStorageChoice() { step = .storageChoice }

    /// Screen 3 → Screen 4.
    func continueLocally() { revealPhrase() }

    private func revealPhrase() {
        do {
            // Resample until the 12 words are distinct. ~3% of phrases contain a
            // duplicate, which complicates the confirm step (two identical bank
            // tiles) for a negligible entropy cost (≈0.04 bits). Bounded retries:
            // statistically 1–2 iterations; the cap only guards against a broken
            // RNG, where generation would have trapped anyway.
            for _ in 0..<32 {
                mnemonic = try bip39.generateMnemonic()
                if Set(mnemonic).count == mnemonic.count { break }
            }
            step = .reveal
        } catch {
            failure = "Couldn't generate a Privacy phrase."
            failureDetail = "\(error)"
            step = .failure
        }
    }

    /// Screen 5 secondary action — back to the words (owner 2026-06-12,
    /// HiFi v1.11.5): the confirm gate proves the user holds a usable RECORD
    /// of the phrase, not their short-term memory. The mnemonic is unchanged;
    /// returning re-enters via `proceedToConfirm()`, which re-shuffles the
    /// target positions and the bank — no answer-memorising shortcut.
    func backToReveal() {
        failure = nil
        flashError = false
        step = .reveal
    }

    /// Screen 4 → Screen 5.
    func proceedToConfirm() {
        targetPositions = Array(0..<mnemonic.count).shuffled().prefix(3).sorted()
        bank = mnemonic.shuffled()
        slots = [nil, nil, nil]
        usedBankIndices = []
        flashError = false
        failure = nil
        step = .confirm
    }

    var targetPositionsForDisplay: [Int] { targetPositions.map { $0 + 1 } }
    var nextSlotIndex: Int? { slots.firstIndex(where: { $0 == nil }) }
    var isLocked: Bool { flashError }

    /// Free-selection tap handler, indexed into `bank`.
    func tapBankWord(at index: Int) {
        guard !flashError else { return }
        guard bank.indices.contains(index) else { return }
        guard !usedBankIndices.contains(index) else { return }
        guard let slot = nextSlotIndex else { return }
        slots[slot] = bank[index]
        usedBankIndices.insert(index)
        if nextSlotIndex == nil {
            validateSlots()
        }
    }

    /// Convenience for tests / callers holding only the word value: taps the
    /// first unused bank tile showing that word.
    func tapBankWord(_ word: String) {
        guard let index = bank.indices.first(where: { bank[$0] == word && !usedBankIndices.contains($0) }) else { return }
        tapBankWord(at: index)
    }

    /// V7 (audit 2026-08, D-228): tapping a filled slot deselects it — the slot's
    /// label promised this to everyone and did nothing for anyone. The word goes
    /// BACK TO THE BANK (one used tile showing it is freed), never lost; the freed
    /// slot is the next to fill, so a mis-placed word is fixed in place. The
    /// bank's by-index usage tracking is preserved: with a duplicate word placed
    /// twice, one deselect frees exactly one tile. Inert while the error flash is
    /// resetting the row, exactly as the bank tiles are.
    func deselectSlot(at slotIndex: Int) {
        guard !flashError else { return }
        guard slots.indices.contains(slotIndex), let word = slots[slotIndex] else { return }
        slots[slotIndex] = nil
        if let bankIndex = bank.indices.first(where: { bank[$0] == word && usedBankIndices.contains($0) }) {
            usedBankIndices.remove(bankIndex)
        }
    }

    private func validateSlots() {
        let expected = targetPositions.map { mnemonic[$0] }
        let got = slots.compactMap { $0 }
        if got == expected {
            // Screen 5 → Screen 6 (the user taps through Screen 6 to finalize).
            step = .complete
        } else {
            flashError = true
            failure = "Those aren't quite right. Try again."
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard let self else { return }
                self.slots = [nil, nil, nil]
                self.usedBankIndices = []
                self.flashError = false
            }
        }
    }

    // MARK: - Restore (existing phrase — cross-device recovery, D-103)

    /// Inline error under the restore field ("that phrase isn't valid …"); nil when clean.
    private(set) var restoreError: String?

    /// Welcome secondary action — "I already use Catchlight".
    func beginRestore() {
        restoreError = nil
        step = .restoreEntry
    }

    /// Restore-screen back action → Welcome.
    func cancelRestore() {
        restoreError = nil
        step = .welcome
    }

    /// Clear the inline restore error as the user edits the field.
    func clearRestoreError() {
        if restoreError != nil { restoreError = nil }
    }

    /// Validate the entered phrase, derive + store the master key, and hand off exactly like
    /// `finishOnboarding` (same storage calls, same `onComplete`). `PhraseRecovery` throws on
    /// a bad checksum / wrong count / unknown word → an inline message, not the failure screen;
    /// a Keychain fault is a real device problem → the failure escape-hatch.
    func submitRestore(_ words: [String]) {
        let cleaned = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let masterKeyData: Data
        do {
            masterKeyData = try PhraseRecovery.recoverMasterKey(from: cleaned, bip39: bip39)
        } catch {
            restoreError = "That doesn't look right. Check the words and try again."
            return
        }
        do {
            // D-253: phrase first, same reasoning as `finishOnboarding` — the
            // `onboarded` gate keys off the master key alone, so the key must not
            // land before the phrase. Less acute on this path (the user typed the
            // phrase and still has it), but the resulting state is identical.
            try MnemonicKeychain.store(cleaned)
            try MasterKeyKeychain.store(masterKeyData)
            onComplete(masterKeyData, /* isRestore: */ true)
        } catch let error as KeychainError {
            failure = "Couldn't secure your account on this device."
            failureDetail = describe(error)
            step = .failure
        } catch {
            failure = "Couldn't secure your account on this device."
            failureDetail = "\(error)"
            step = .failure
        }
    }

    // MARK: - Completion

    /// Screen 6 "Start using Catchlight" — derive + store master key.
    func finishOnboarding() {
        do {
            let masterKeyData = MasterKeyDerivation.deriveRaw(from: mnemonic)
            // D-253: the PHRASE IS STORED FIRST, deliberately. `Wiring.swift` decides
            // `onboarded` from `MasterKeyKeychain.exists()` ALONE, so the moment the
            // master key lands this install counts as onboarded on the next launch.
            // With the old order — key first, phrase second — any failure or kill
            // between the two left a working app holding a master key, NO phrase, and
            // no warning: exactly the condition recorded as D-249, and unrecoverable,
            // because the phrase is the only key and this one has never been shown to
            // anyone yet. Storing the phrase first means the app cannot come to believe
            // it is onboarded until the phrase is already safe; a failure here simply
            // leaves the user to onboard again.
            //
            // Persists the mnemonic so Settings → Privacy phrase can re-display it
            // (Task 3.12). Carries `.userPresence` access control — the fresh iOS
            // auth is the whole gate (the in-app PIN was removed by D-042). (The
            // Argon2 metadata salt is no longer written — HKDF derivation uses a
            // fixed domain salt.)
            try MnemonicKeychain.store(mnemonic)
            try MasterKeyKeychain.store(masterKeyData)
            onComplete(masterKeyData, /* isRestore: */ false)
        } catch let error as KeychainError {
            failure = "Couldn't secure your account on this device."
            failureDetail = describe(error)
            step = .failure
        } catch {
            failure = "Couldn't secure your account on this device."
            failureDetail = "\(error)"
            step = .failure
        }
    }

    private func describe(_ error: KeychainError) -> String {
        switch error {
        case .storeFailed(let status):       return "Keychain store failed (OSStatus \(status))."
        case .retrieveFailed(let status):    return "Keychain retrieve failed (OSStatus \(status))."
        case .accessControlCreationFailed:   return "Keychain access control could not be created."
        case .notFound:                      return "Keychain item not found."
        case .secureEnclaveFailed(let detail): return "Secure Enclave operation failed: \(detail)"
        case .malformedStoredKey:            return "Stored key data was malformed."
        }
    }

    /// Escape hatch — returns the user to welcome so they can restart cleanly.
    func restartFromError() {
        mnemonic = []
        targetPositions = []
        bank = []
        slots = [nil, nil, nil]
        usedBankIndices = []
        flashError = false
        failure = nil
        failureDetail = nil
        step = .welcome
    }
}
