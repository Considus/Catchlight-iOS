//
//  OnboardingView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  Six-screen onboarding (UX Session Decisions v2.5 §15):
//    1. welcome → 2. storageChoice → (3. localWarning) → 4. reveal → 5. confirm → 6. complete
//  All copy in this file is the locked spec text — do not paraphrase.
//

import SwiftUI
import CatchlightCore

struct OnboardingView: View {
    @Environment(OnboardingViewModel.self) private var vm

    var body: some View {
        Group {
            switch vm.step {
            case .welcome:        WelcomeStep()
            case .storageChoice:  StorageChoiceStep()
            case .localWarning:   LocalWarningStep()
            case .reveal:         RevealStep()
            case .confirm:        ConfirmStep()
            case .complete:       CompleteStep()
            case .failure:        FailureStep()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared chrome

/// Wraps a step's content with a full-bleed background, edge-padded body, and an
/// optional bottom-pinned button row (above the home indicator). Every step uses
/// this so the layout pattern is consistent and no screen ever clips its button.
private struct StepScaffold<Content: View, Bottom: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var bottom: () -> Bottom

    // At accessibility text sizes (AX1+) wrap the content in a ScrollView so tall
    // onboarding screens (Welcome, Storage Choice, Cloud Reminder) don't clip
    // behind the bottom safe-area inset. At default sizes the existing
    // Spacer-centred ZStack is preserved so visuals are unchanged. Steps 4–5
    // already contain their own ScrollView; SwiftUI nests these cleanly.
    @Environment(\.dynamicTypeSize) private var dynamicSize

    var body: some View {
        Group {
            if dynamicSize.isAccessibilitySize {
                ScrollView {
                    content()
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                }
            } else {
                ZStack {
                    content()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ckBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            bottom()
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .background(Color.ckBackground.ignoresSafeArea(edges: .bottom))
        }
    }
}

private struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
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

private struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CatchlightFont.ui(.medium, size: 17, relativeTo: .body))
                .foregroundStyle(Color.ckTextPrimary)
                .frame(maxWidth: .infinity, minHeight: CatchlightLayout.minTouchTarget)
                .background(
                    Capsule().stroke(Color.ckTextPrimary.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Screen 1: Welcome

private struct WelcomeStep: View {
    @Environment(OnboardingViewModel.self) private var vm

    var body: some View {
        StepScaffold {
            VStack(spacing: 24) {
                Spacer()
                Image("catchlight-icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Image("catchlight-wordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 32)
                    .accessibilityLabel("Catchlight")
                Text("You don't need to choose privacy, it's your right and you never need to ask for it.")
                    .font(CatchlightFont.displayFixed(size: 26))
                    .foregroundStyle(Color.ckTextPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 16) {
                    (Text("First, we'll create your privacy phrase — 12 words that are the ")
                     + Text("only").bold()
                     + Text(" key to your data."))
                        .font(CatchlightFont.ui(.light, size: 17, relativeTo: .body))
                        .foregroundStyle(Color.ckTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("We never see them, store them, or ask for them.")
                        .font(CatchlightFont.ui(.light, size: 17, relativeTo: .body))
                        .foregroundStyle(Color.ckTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.top, 32)
        } bottom: {
            PrimaryButton(title: "Create my privacy phrase") { vm.beginStorageChoice() }
        }
    }
}

// MARK: - Screen 2: Storage choice

private struct StorageChoiceStep: View {
    @Environment(OnboardingViewModel.self) private var vm

    var body: some View {
        StepScaffold {
            VStack(spacing: 24) {
                Spacer().frame(height: 8)
                Text("Takes belong to you and so does the choice of how they are stored.")
                    .font(CatchlightFont.displayFixed(size: 26))
                    .foregroundStyle(Color.ckTextPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 24)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)

                StorageOptionCard(
                    title: "Local — on this device only",
                    description: "Your Takes stay on this device. If you lose it without a backup, they're gone."
                ) { vm.chooseStorage(.local) }

                StorageOptionCard(
                    title: "Cloud — backed up and restorable",
                    description: "Connect a cloud folder you control. Your Takes sync encrypted — we never see them."
                ) { vm.chooseStorage(.cloud) }

                Spacer(minLength: 0)
            }
        } bottom: {
            EmptyView()
        }
    }
}

private struct StorageOptionCard: View {
    let title: String
    let description: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(CatchlightFont.ui(.medium, size: 17, relativeTo: .body))
                    .foregroundStyle(Color.ckTextPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(description)
                    .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Color.ckTextSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.ckSurface)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
    }
}

// MARK: - Screen 3: Local warning

private struct LocalWarningStep: View {
    @Environment(OnboardingViewModel.self) private var vm

    var body: some View {
        StepScaffold {
            VStack(spacing: 24) {
                Spacer()
                Text("One thing before we continue.")
                    .font(CatchlightFont.displayFixed(size: 28))
                    .foregroundStyle(Color.ckTextPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Without cloud backup, your Takes exist only on this device. If you lose access to it and haven't set up a second device, your data cannot be recovered.")
                    .font(CatchlightFont.ui(.light, size: 17, relativeTo: .body))
                    .foregroundStyle(Color.ckTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        } bottom: {
            VStack(spacing: 12) {
                PrimaryButton(title: "Continue locally") { vm.continueLocally() }
                SecondaryButton(title: "Go back") { vm.backToStorageChoice() }
            }
        }
    }
}

// MARK: - Screen 4: Reveal

private struct RevealStep: View {
    @Environment(OnboardingViewModel.self) private var vm

    private var bodyText: String {
        switch vm.storagePath {
        case .local:
            return "Write these 12 words down and keep them somewhere safe. They encrypt your Takes and enable a second device."
        case .cloud:
            return "Write these 12 words down and keep them somewhere safe. Together with your cloud folder, they're how you restore your Takes on any device."
        }
    }

    var body: some View {
        StepScaffold {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Your privacy phrase")
                        .font(CatchlightFont.displayFixed(size: 30))
                        .foregroundStyle(Color.ckTextPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 48) // clear the dynamic island

                    Text(bodyText)
                        .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .subheadline))
                        .foregroundStyle(Color.ckTextObie)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    wordGrid(words: vm.mnemonic)
                        .padding(.top, 4)
                }
                .padding(.bottom, 100) // clear the pinned button
            }
        } bottom: {
            PrimaryButton(title: "I've written them down") { vm.proceedToConfirm() }
        }
    }

    private func wordGrid(words: [String]) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                HStack(spacing: 8) {
                    Text("\(idx + 1)")
                        .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .caption))
                        .foregroundStyle(Color.ckTextSecondary)
                        .frame(width: 22, alignment: .trailing)
                    Text(word)
                        .font(CatchlightFont.displayFixed(size: 20))
                        .foregroundStyle(Color.ckTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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
}

// MARK: - Screen 5: Confirm

private struct ConfirmStep: View {
    @Environment(OnboardingViewModel.self) private var vm

    var body: some View {
        StepScaffold {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Confirm three words")
                        .font(CatchlightFont.displayFixed(size: 30))
                        .foregroundStyle(Color.ckTextPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 48) // clear the dynamic island

                    Text(promptCopy)
                        .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .subheadline))
                        .foregroundStyle(Color.ckTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    slotsRow

                    if let failure = vm.failure {
                        Text(failure)
                            .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .caption))
                            .foregroundStyle(Color.ckEmber)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    bankGrid
                }
                .padding(.bottom, 24)
            }
        } bottom: {
            // A 1-pt clear strip rather than EmptyView. On iOS 26, a ScrollView
            // inside StepScaffold whose `.safeAreaInset(.bottom)` closure returns
            // EmptyView lays its content above the top safe-area edge (off-screen).
            // Giving the inset a real (zero-visual) view restores normal layout.
            Color.clear.frame(height: 1)
        }
    }

    private var promptCopy: String {
        let positions = vm.targetPositionsForDisplay
        guard positions.count == 3 else {
            return "Tap the words from your phrase, in order."
        }
        return "Tap words \(positions[0]), \(positions[1]) and \(positions[2]) from your phrase, in order."
    }

    private var slotsRow: some View {
        HStack(spacing: 12) {
            ForEach(0..<vm.slots.count, id: \.self) { i in
                let value = vm.slots[i]
                let positionLabel = vm.targetPositionsForDisplay.indices.contains(i)
                    ? "\(vm.targetPositionsForDisplay[i])"
                    : ""
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(vm.flashError ? Color.ckEmber : Color.ckSpine, lineWidth: 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(vm.flashError ? Color.ckEmber.opacity(0.18) : Color.ckSurface.opacity(0.6))
                        )
                    VStack(spacing: 2) {
                        Text(positionLabel)
                            .font(CatchlightFont.ui(.regular, size: 11, relativeTo: .caption2))
                            .foregroundStyle(Color.ckTextSecondary)
                        Text(value ?? "—")
                            .font(CatchlightFont.displayFixed(size: 18))
                            .foregroundStyle(value == nil ? Color.ckTextSecondary : Color.ckTextPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 6)
                }
                .frame(minHeight: 56)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.18), value: vm.flashError)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    value.map { "Slot \(positionLabel): \($0). Double-tap to deselect." }
                    ?? "Slot \(positionLabel), empty"
                )
                .accessibilityHint(value == nil ? "Pick a word from the bank below." : "")
                .accessibilityAddTraits(value != nil ? [.isButton] : [])
            }
        }
    }

    private var bankGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            // Index-based identity + usage (2026-06-10): tracking by word value
            // greyed BOTH tiles when a phrase contained a duplicate word, and
            // could make the confirm step unwinnable.
            ForEach(Array(vm.bank.enumerated()), id: \.offset) { index, word in
                let used = vm.usedBankIndices.contains(index)
                Button { vm.tapBankWord(at: index) } label: {
                    Text(word)
                        .font(CatchlightFont.displayFixed(size: 18))
                        .foregroundStyle(used ? Color.ckTextSecondary.opacity(0.4) : Color.ckTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: CatchlightLayout.minTouchTarget)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.ckSurface.opacity(used ? 0.35 : 1.0))
                        )
                }
                .buttonStyle(.plain)
                .disabled(used || vm.isLocked)
                .accessibilityLabel(used ? "\(word), already placed" : "Select \(word)")
                .accessibilityHint(used ? "Already placed." : "Double-tap to place in the next slot.")
            }
        }
    }
}

// MARK: - Screen 6: Complete

private struct CompleteStep: View {
    @Environment(OnboardingViewModel.self) private var vm

    private var bodyText: String {
        switch vm.storagePath {
        case .local:
            return "Your Takes are yours. Encrypted on this device, readable only by you."
        case .cloud:
            return "Your Takes are yours. Encrypted on this device and backed up to your cloud folder — readable only by you."
        }
    }

    var body: some View {
        StepScaffold {
            VStack(spacing: 24) {
                Spacer()
                Image("catchlight-icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text("You're ready.")
                    .font(CatchlightFont.displayFixed(size: 32))
                    .foregroundStyle(Color.ckTextPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(bodyText)
                    .font(CatchlightFont.ui(.light, size: 17, relativeTo: .body))
                    .foregroundStyle(Color.ckTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        } bottom: {
            PrimaryButton(title: "Start using Catchlight") { vm.finishOnboarding() }
        }
    }
}

// MARK: - Failure (escape hatch)

private struct FailureStep: View {
    @Environment(OnboardingViewModel.self) private var vm

    var body: some View {
        StepScaffold {
            VStack(spacing: 20) {
                Spacer()
                Text(vm.failure ?? "Something went wrong.")
                    .font(CatchlightFont.displayFixed(size: 26))
                    .foregroundStyle(Color.ckTextPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = vm.failureDetail {
                    Text(detail)
                        .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .caption))
                        .foregroundStyle(Color.ckTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }
                Text("You can start over and try again. Your phrase hasn't been saved anywhere.")
                    .font(CatchlightFont.ui(.light, size: 15, relativeTo: .body))
                    .foregroundStyle(Color.ckTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        } bottom: {
            PrimaryButton(title: "Start over") { vm.restartFromError() }
        }
    }
}

// MARK: - Previews

#Preview("Onboarding — welcome (Night)") {
    let vm = OnboardingViewModel(onComplete: {})
    return OnboardingView()
        .environment(vm)
        .preferredColorScheme(.dark)
}

#Preview("Onboarding — reveal (Night)") {
    let vm = OnboardingViewModel(onComplete: {})
    vm.beginStorageChoice()
    vm.chooseStorage(.cloud)
    return OnboardingView()
        .environment(vm)
        .preferredColorScheme(.dark)
}

#Preview("Onboarding — confirm (Daylight)") {
    let vm = OnboardingViewModel(onComplete: {})
    vm.beginStorageChoice()
    vm.chooseStorage(.cloud)
    vm.proceedToConfirm()
    return OnboardingView()
        .environment(vm)
        .preferredColorScheme(.light)
}
