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
    private(set) var usedWords: Set<String> = []
    private(set) var flashError: Bool = false

    private(set) var failure: String?
    private(set) var failureDetail: String?

    private let bip39: BIP39
    private let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
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
            mnemonic = try bip39.generateMnemonic()
            step = .reveal
        } catch {
            failure = "Couldn't generate a privacy phrase."
            failureDetail = "\(error)"
            step = .failure
        }
    }

    /// Screen 4 → Screen 5.
    func proceedToConfirm() {
        targetPositions = Array(0..<mnemonic.count).shuffled().prefix(3).sorted()
        bank = mnemonic.shuffled()
        slots = [nil, nil, nil]
        usedWords = []
        flashError = false
        failure = nil
        step = .confirm
    }

    var targetPositionsForDisplay: [Int] { targetPositions.map { $0 + 1 } }
    var nextSlotIndex: Int? { slots.firstIndex(where: { $0 == nil }) }
    var isLocked: Bool { flashError }

    /// Free-selection tap handler — Pass 1 logic, unchanged.
    func tapBankWord(_ word: String) {
        guard !flashError else { return }
        guard !usedWords.contains(word) else { return }
        guard let slot = nextSlotIndex else { return }
        slots[slot] = word
        usedWords.insert(word)
        if nextSlotIndex == nil {
            validateSlots()
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
            failure = "Those aren't quite right — try again."
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard let self else { return }
                self.slots = [nil, nil, nil]
                self.usedWords = []
                self.flashError = false
            }
        }
    }

    var isConfirmed: Bool {
        guard slots.allSatisfy({ $0 != nil }) else { return false }
        return slots.compactMap { $0 } == targetPositions.map { mnemonic[$0] }
    }

    // MARK: - Completion

    /// Screen 6 "Start using Catchlight" — derive + store master key.
    func finishOnboarding() {
        do {
            let masterKeyData = MasterKeyDerivation.deriveRaw(from: mnemonic)
            try MasterKeyKeychain.store(masterKeyData)
            persistMetadataSalt(SecureRandom.bytes(16))
            onComplete()
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
        }
    }

    /// Escape hatch — returns the user to welcome so they can restart cleanly.
    func restartFromError() {
        mnemonic = []
        targetPositions = []
        bank = []
        slots = [nil, nil, nil]
        usedWords = []
        flashError = false
        failure = nil
        failureDetail = nil
        step = .welcome
    }

    private func persistMetadataSalt(_ salt: Data) {
        UserDefaults(suiteName: AppGroup.identifier)?
            .set(salt.base64EncodedString(), forKey: "catchlight.argon2SaltB64")
    }
}
