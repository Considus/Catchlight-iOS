//
//  AppModel.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  The application-scope model: holds the shared UIState and the feature view
//  models, and decides onboarding vs. main app. Built once by Wiring at launch and
//  injected into the environment. @Observable (iOS 17+).
//
//  It does NOT construct the SQLCipher store itself — that requires the Keychain
//  master key, which only exists after onboarding. The store is supplied (post-
//  onboarding) by Wiring, so AppModel stays free of platform crypto wiring and is
//  trivially previewable with an InMemoryTakeStore.
//

import SwiftUI
import Observation
import CatchlightCore

@Observable
final class AppModel {

    let ui = UIState()

    private(set) var needsOnboarding: Bool
    private(set) var onboardingVM: OnboardingViewModel?

    // Feature view models. Available once a store is bound (after onboarding).
    private(set) var dailiesVM: DailiesViewModel
    private(set) var searchVM: SearchViewModel
    private(set) var sequenceVM: SequenceViewModel

    private let argon2: Argon2idDeriving
    /// Supplies the production store after the master key exists. Injected by Wiring.
    private let storeProvider: () -> TakeStore?

    init(argon2: Argon2idDeriving,
         needsOnboarding: Bool,
         initialStore: TakeStore,
         storeProvider: @escaping () -> TakeStore?) {
        self.argon2 = argon2
        self.needsOnboarding = needsOnboarding
        self.storeProvider = storeProvider
        self.dailiesVM = DailiesViewModel(store: initialStore)
        self.searchVM = SearchViewModel(store: initialStore)
        self.sequenceVM = SequenceViewModel(store: initialStore)

        if needsOnboarding {
            self.onboardingVM = nil
            self.onboardingVM = OnboardingViewModel(argon2: argon2) { [weak self] in
                self?.completeOnboarding()
            }
        }
    }

    /// Called by OnboardingViewModel after the master key is stored. Rebinds the
    /// feature view models to the now-openable production store and seeds the first
    /// Takes, then flips to the main app.
    private func completeOnboarding() {
        if let store = storeProvider() {
            seedIfEmpty(store)
            rebind(to: store)
        }
        onboardingVM = nil
        needsOnboarding = false
    }

    private func seedIfEmpty(_ store: TakeStore) {
        if (try? store.allTakes())?.isEmpty ?? true {
            for take in SeedTakes.make() { try? store.upsert(take) }
        }
    }

    private func rebind(to store: TakeStore) {
        dailiesVM = DailiesViewModel(store: store)
        searchVM = SearchViewModel(store: store)
        sequenceVM = SequenceViewModel(store: store)
    }

    // MARK: - Previews

    static func preview(store: TakeStore, onboarded: Bool) -> AppModel {
        AppModel(
            argon2: PreviewArgon2(),
            needsOnboarding: !onboarded,
            initialStore: store,
            storeProvider: { store }
        )
    }
}

/// Deterministic Argon2 double for previews only.
private struct PreviewArgon2: Argon2idDeriving {
    func deriveKey(passwordBytes: [UInt8], saltBytes: [UInt8], parameters: Argon2Parameters) throws -> Data {
        Data(repeating: 0x42, count: parameters.outputLength)
    }
}
