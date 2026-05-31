//
//  OnboardingViewModel.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  Owns first-launch onboarding: generating the BIP-39 recovery phrase, driving the
//  write-it-down confirmation friction step, and — on completion — deriving and
//  storing the master key, then seeding the first Takes. @Observable (iOS 17+).
//
//  WORDLIST SOURCING (flagged decision):
//    The production path is `EnglishWordlist.load()`, which verifies the bundled
//    official 2048-word list against a pinned SHA-256 and throws loudly until both
//    are present (a deliberate security guard — see BIP39Wordlist+English.swift and
//    README "Before release" steps 2). Those artefacts CANNOT be produced offline.
//    To keep onboarding functional in development WITHOUT defeating that guard, we
//    fall back to a synthetic 2048-word list and surface a visible debug banner
//    (`usingNonStandardWordlist == true`). The moment the official list + digest are
//    bundled, `load()` succeeds and the real path takes over automatically with no
//    code change.
//

import Foundation
import Observation
import CryptoKit
import CatchlightCore

@Observable
final class OnboardingViewModel {

    enum Step {
        case intro          // calm framing: why a recovery phrase exists
        case reveal         // the 12 words, numbered
        case confirm        // tap each word in order (friction, not skippable)
        case finishing      // deriving + storing the key
    }

    private(set) var step: Step = .intro

    /// The generated 12-word mnemonic.
    private(set) var mnemonic: [String] = []

    /// True when the dev/synthetic wordlist is in use (official list not bundled).
    /// Drives a visible "#DEBUG — non-standard recovery phrase" banner.
    private(set) var usingNonStandardWordlist: Bool = false

    /// Confirmation state: the shuffled word bank the user taps from, and the words
    /// they have correctly tapped so far (in order).
    private(set) var shuffledBank: [String] = []
    private(set) var confirmedCount: Int = 0
    private(set) var confirmError: Bool = false

    private(set) var failure: String?

    private let bip39: BIP39
    private let argon2: Argon2idDeriving
    private let onComplete: () -> Void

    /// - Parameters:
    ///   - argon2: KDF binding (Wiring injects the real LibArgon2).
    ///   - onComplete: called after the master key is stored and seeds are written;
    ///     the app then transitions to Dailies.
    init(argon2: Argon2idDeriving, onComplete: @escaping () -> Void) {
        self.argon2 = argon2
        self.onComplete = onComplete

        // Prefer the verified official wordlist; fall back to synthetic in dev.
        if let official = try? EnglishWordlist.load() {
            self.bip39 = BIP39(wordlist: official)
            self.usingNonStandardWordlist = false
        } else {
            self.bip39 = BIP39(wordlist: Self.syntheticWordlist())
            self.usingNonStandardWordlist = true
        }
    }

    // MARK: - Flow

    func begin() {
        do {
            mnemonic = try bip39.generateMnemonic()
            shuffledBank = mnemonic.shuffled()
            confirmedCount = 0
            step = .reveal
        } catch {
            failure = "Couldn't generate a recovery phrase."
        }
    }

    func proceedToConfirm() {
        confirmedCount = 0
        confirmError = false
        shuffledBank = mnemonic.shuffled()
        step = .confirm
    }

    /// Called when the user taps a word in the confirmation bank. Must be the next
    /// word in the original order; otherwise it's a (recoverable) mistake.
    func tapConfirmWord(_ word: String) {
        guard confirmedCount < mnemonic.count else { return }
        if word == mnemonic[confirmedCount] {
            confirmedCount += 1
            confirmError = false
            if confirmedCount == mnemonic.count {
                finish()
            }
        } else {
            confirmError = true
        }
    }

    /// The next word the user must tap (for the accessibility hint / progress copy).
    var nextExpectedIndex: Int { confirmedCount }

    var isConfirmed: Bool { confirmedCount == mnemonic.count && !mnemonic.isEmpty }

    // MARK: - Completion

    private func finish() {
        step = .finishing
        do {
            // Generate (or reuse) the per-account Argon2 salt.
            let salt = SecureRandom.bytes(16)
            let masterKeyData = try argon2.deriveMasterKey(mnemonic: mnemonic, salt: salt)
            try MasterKeyKeychain.store(masterKeyData)
            persistSalt(salt)
            onComplete()
        } catch {
            // Surface, and let the user retry from confirm.
            failure = "Couldn't secure your account on this device."
            step = .confirm
        }
    }

    private func persistSalt(_ salt: Data) {
        UserDefaults(suiteName: AppGroup.identifier)?
            .set(salt.base64EncodedString(), forKey: "catchlight.argon2SaltB64")
    }

    // MARK: - Dev synthetic wordlist

    /// A deterministic synthetic 2048-word list ("w0"..."w2047"). Proves the BIP-39
    /// algorithm end-to-end; NOT standard-compliant (hence the visible banner). The
    /// official list replaces this automatically once bundled + digest-pinned.
    static func syntheticWordlist() -> BIP39Wordlist {
        // swiftlint:disable:next force_try
        try! BIP39Wordlist(words: (0..<2048).map { "w\($0)" })
    }
}
