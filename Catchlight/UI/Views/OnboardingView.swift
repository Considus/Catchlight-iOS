//
//  OnboardingView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  Six-screen onboarding (UX Session Decisions v2.5 §15):
//    1. welcome → 2. storageChoice → (3. localWarning) → 4. reveal → 5. confirm → 6. complete
//  All copy in this file is the locked spec text — do not paraphrase.
//  Copy source of truth: the 2026-06-12 owner revision — HiFi v1.7
//  (internal v1.11.1 changelog) — which supersedes UX §15 where they differ.
//

import SwiftUI
import CatchlightCore

struct OnboardingView: View {
    @Environment(OnboardingViewModel.self) private var vm

    var body: some View {
        // Step changes CROSSFADE the whole content layer (owner motion rule
        // 2026-06-12: the app-wide heading-crossfade extended to onboarding —
        // DS §10 fade duration; nothing snaps). Persistent chrome (the
        // background, the dock-geometry button row position) holds steady;
        // within-step changes (error line, slot fills) animate individually.
        ZStack {
            stepView
                .id(vm.step)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.18), value: vm.step)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var stepView: some View {
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
            // No scaffold padding here — DockPillRow carries the dock grid's
            // own paddings so the pills land exactly on the dock positions.
            // Background = the dock's soft edge (owner 2026-06-12, HiFi
            // v1.11.5): scrolling content fades out beneath the button zone
            // instead of meeting a hard edge.
            bottom()
                .frame(maxWidth: .infinity)
                .dockFadeBackground()
        }
    }
}

// (DaylightCardShadow lives in CatchlightTheme.swift — shared with the
// Settings sub-screens since 2026-06-12.)

// Onboarding buttons use the shared dock-geometry pills (DockPillRow.swift) —
// owner decision 2026-06-12 (HiFi v1.11.1): a single pill sits exactly over
// the four dock-button slots; pairs split into slots 1+2 / 3+4.

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
                Text("You don't need to choose privacy, it's yours and you never have to ask for it.")
                    .font(CatchlightFont.displayFixed(size: 26))
                    .foregroundStyle(Color.ckTextPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 16) {
                    (Text("First, we'll create your privacy phrase — 12 words that are the ")
                     + Text("ONLY").bold()
                     + Text(" key to your data."))
                        .font(CatchlightFont.ui(.light, size: 17, relativeTo: .body))
                        .foregroundStyle(Color.ckTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("We never see them, store them, or ask for them. So don't lose them.")
                        .font(CatchlightFont.ui(.light, size: 17, relativeTo: .body))
                        .foregroundStyle(Color.ckTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.top, 32)
        } bottom: {
            DockPillRow {
                DockPill(title: "Create my privacy phrase") { vm.beginStorageChoice() }
            }
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
                    description: "Connect a cloud folder you control. Your Takes remain encrypted — we never see them."
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
                    .daylightCardShadow()
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
            DockPillRow {
                DockPill(title: "I know the risk") { vm.continueLocally() }
            } trailing: {
                DockPill(title: "Go back", secondary: true) { vm.backToStorageChoice() }
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

                    // ckTextSecondary, matching the confirm prompt (owner
                    // 2026-06-12, HiFi v1.11.5 — the amber treatment retired).
                    Text(bodyText)
                        .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .subheadline))
                        .foregroundStyle(Color.ckTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    wordGrid(words: vm.mnemonic)
                        .padding(.top, 4)
                }
                .padding(.bottom, 100) // clear the pinned button
            }
        } bottom: {
            DockPillRow {
                DockPill(title: "I've written them down") { vm.proceedToConfirm() }
            }
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
                        .daylightCardShadow()
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

                    // The error line is RESERVED (owner 2026-06-12, HiFi
                    // v1.11.1): it always occupies its height so the bank
                    // never moves when the message appears. ckTextObie, not
                    // ckEmber: Ember fails WCAG AA on Paper at 13pt (DS §12.3);
                    // resolves to Ember Text #856539 Daylight / Glow Night.
                    Text(vm.failure ?? " ")
                        .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .caption))
                        .foregroundStyle(Color.ckTextObie)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(vm.failure == nil ? 0 : 1)
                        .accessibilityHidden(vm.failure == nil)

                    bankGrid
                }
                .padding(.bottom, 24)
            }
        } bottom: {
            // Reveal-return (owner 2026-06-12, HiFi v1.11.5): a user who blanks
            // on a word must never be stuck guessing — the gate proves a usable
            // record of the phrase, not short-term memory. Re-entry re-shuffles.
            // (Also supersedes the old iOS 26 EmptyView-inset workaround: the
            // inset now always holds a real view.)
            DockPillRow {
                DockPill(title: "Show my words once more", secondary: true) {
                    vm.backToReveal()
                }
            }
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
        // 2×6 — the same grid as the reveal step (owner 2026-06-12, HiFi
        // v1.11.3), order preserved from the shuffle.
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
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
                                .daylightCardShadow()
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
            DockPillRow {
                DockPill(title: "Start using Catchlight") { vm.finishOnboarding() }
            }
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
                Text("You can start over and try again. Your phrase hasn't been saved anywhere. We'll generate another.")
                    .font(CatchlightFont.ui(.light, size: 15, relativeTo: .body))
                    .foregroundStyle(Color.ckTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        } bottom: {
            DockPillRow {
                DockPill(title: "Start over") { vm.restartFromError() }
            }
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
