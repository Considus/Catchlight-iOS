//
//  OnboardingView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  First-launch onboarding. Tone: calm and clear — privacy as infrastructure, not a
//  threat warning. Four steps (intro → reveal → confirm → finishing):
//    • intro:    why a recovery phrase exists, framed plainly.
//    • reveal:   the 12 numbered words in a readable Cormorant layout, with the one
//                non-negotiable instruction: write these down; they can't be recovered.
//    • confirm:  tap each word in order — a deliberate friction step, not skippable.
//    • finishing: derive + store the master key, then transition to Dailies.
//
//  A visible "#DEBUG — non-standard recovery phrase" banner appears when the
//  synthetic dev wordlist is in use (official list not yet bundled). See
//  OnboardingViewModel for the sourcing decision.
//

import SwiftUI
import CatchlightCore

struct OnboardingView: View {
    @Environment(OnboardingViewModel.self) private var vm
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ZStack {
            Color.ckBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                if vm.usingNonStandardWordlist {
                    debugBanner
                }

                switch vm.step {
                case .intro:     intro
                case .reveal:    reveal
                case .confirm:   confirm
                case .finishing: finishing
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Debug banner

    private var debugBanner: some View {
        Text("#DEBUG — non-standard recovery phrase (official wordlist not bundled)")
            .font(CatchlightFont.ui(.medium, size: 11, relativeTo: .caption2))
            .foregroundStyle(Color.ckInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.ckEmber)
            .accessibilityLabel("Debug: non-standard recovery phrase in use. The official wordlist is not bundled.")
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("catchlight")
                .font(CatchlightFont.display(size: 44, relativeTo: .largeTitle))
                .foregroundStyle(Color.ckTextPrimary)
            Text("Your takes are encrypted on this device and only this device. No account, no server, no one else — not even us.")
                .font(CatchlightFont.ui(.light, size: 17, relativeTo: .body))
                .foregroundStyle(Color.ckTextSecondary)
                .multilineTextAlignment(.center)
            Text("So that you never lose access, you'll get a 12-word recovery phrase. It's the one and only key. Keep it somewhere safe.")
                .font(CatchlightFont.ui(.light, size: 17, relativeTo: .body))
                .foregroundStyle(Color.ckTextSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            primaryButton("Show my recovery phrase") { vm.begin() }
        }
        .padding(.vertical, 32)
    }

    // MARK: - Reveal

    private var reveal: some View {
        VStack(spacing: 20) {
            Text("Your recovery phrase")
                .font(CatchlightFont.display(size: 30, relativeTo: .title))
                .foregroundStyle(Color.ckTextPrimary)
                .padding(.top, 24)

            Text("Write these twelve words down, in order, and store them somewhere safe. They cannot be recovered if lost.")
                .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .subheadline))
                .foregroundStyle(Color.ckTextObie)
                .multilineTextAlignment(.center)

            wordGrid(words: vm.mnemonic, numbered: true)

            Spacer()
            primaryButton("I've written it down") { vm.proceedToConfirm() }
        }
        .padding(.vertical, 16)
    }

    private func wordGrid(words: [String], numbered: Bool) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                HStack(spacing: 8) {
                    if numbered {
                        Text("\(idx + 1)")
                            .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .caption))
                            .foregroundStyle(Color.ckTextSecondary)
                            .frame(width: 22, alignment: .trailing)
                    }
                    Text(word)
                        .font(CatchlightFont.display(size: 20, relativeTo: .body))
                        .foregroundStyle(Color.ckTextPrimary)
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.ckSurface)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Word \(idx + 1): \(word)")
            }
        }
    }

    // MARK: - Confirm

    private var confirm: some View {
        VStack(spacing: 20) {
            Text("Confirm your phrase")
                .font(CatchlightFont.display(size: 30, relativeTo: .title))
                .foregroundStyle(Color.ckTextPrimary)
                .padding(.top, 24)

            Text("Tap the words in order, from first to last.")
                .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .subheadline))
                .foregroundStyle(Color.ckTextSecondary)
                .multilineTextAlignment(.center)

            // Progress.
            Text("\(vm.confirmedCount) of \(vm.mnemonic.count)")
                .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .subheadline))
                .foregroundStyle(vm.confirmError ? Color.ckEmber : Color.ckTextObie)
                .accessibilityLabel(vm.confirmError
                                    ? "Wrong word. \(vm.confirmedCount) of \(vm.mnemonic.count) confirmed."
                                    : "\(vm.confirmedCount) of \(vm.mnemonic.count) confirmed.")

            if vm.confirmError {
                Text("That's not the next word — try again.")
                    .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .caption))
                    .foregroundStyle(Color.ckEmber)
            }

            // Word bank.
            let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(vm.shuffledBank.enumerated()), id: \.offset) { _, word in
                    Button { vm.tapConfirmWord(word) } label: {
                        Text(word)
                            .font(CatchlightFont.display(size: 18, relativeTo: .body))
                            .foregroundStyle(Color.ckTextPrimary)
                            .frame(maxWidth: .infinity, minHeight: CatchlightLayout.minTouchTarget)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.ckSurface)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(word)
                    .accessibilityHint("Double-tap if this is the next word in your phrase.")
                }
            }

            if let failure = vm.failure {
                Text(failure)
                    .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .caption))
                    .foregroundStyle(Color.ckEmber)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(.vertical, 16)
    }

    // MARK: - Finishing

    private var finishing: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .tint(Color.ckTextObie)
            Text("Securing your account on this device…")
                .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                .foregroundStyle(Color.ckTextSecondary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Securing your account on this device.")
    }

    // MARK: - Shared

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CatchlightFont.ui(.medium, size: 17, relativeTo: .body))
                .foregroundStyle(Color.ckBackground)
                .frame(maxWidth: .infinity, minHeight: CatchlightLayout.minTouchTarget)
                .background(Capsule().fill(Color.ckAdd))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("Double-tap to continue.")
    }
}

#Preview("Onboarding — intro (Night)") {
    let vm = OnboardingViewModel(argon2: PreviewArgon2(), onComplete: {})
    return OnboardingView()
        .environment(vm)
        .preferredColorScheme(.dark)
}

#Preview("Onboarding — reveal (Night)") {
    let vm = OnboardingViewModel(argon2: PreviewArgon2(), onComplete: {})
    vm.begin()
    return OnboardingView()
        .environment(vm)
        .preferredColorScheme(.dark)
}

#Preview("Onboarding — confirm (Daylight)") {
    let vm = OnboardingViewModel(argon2: PreviewArgon2(), onComplete: {})
    vm.begin()
    vm.proceedToConfirm()
    return OnboardingView()
        .environment(vm)
        .preferredColorScheme(.light)
}

/// A deterministic Argon2 double for previews only — never used in the app.
private struct PreviewArgon2: Argon2idDeriving {
    func deriveKey(passwordBytes: [UInt8], saltBytes: [UInt8], parameters: Argon2Parameters) throws -> Data {
        Data(repeating: 0x42, count: parameters.outputLength)
    }
}
