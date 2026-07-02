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

/// The fixed gap below the brand mark at which EVERY onboarding hero line (the
/// Cormorant italic heading or, on the splash, the tagline) sits — so they land at
/// the same Y on every screen the brand mark appears: splash · Welcome · Storage ·
/// Local warning · Reveal · Confirm · Complete (owner 2026-06-16). Without this the
/// flexible spacers pushed each heading down by an amount that depended on the
/// content below it, so they drifted apart.
private let introHeroTopGap: CGFloat = CatchlightLayout.introHeroTopGap

struct OnboardingView: View {
    @Environment(OnboardingViewModel.self) private var vm

    var body: some View {
        // Step changes CROSSFADE the whole content layer (owner motion rule
        // 2026-06-12: the app-wide heading-crossfade extended to onboarding —
        // DS §10 fade duration; nothing snaps). Persistent chrome (the
        // background, the dock-geometry button row position) holds steady;
        // within-step changes (error line, slot fills) animate individually.
        ZStack(alignment: .top) {
            stepView
                .id(vm.step)
                .transition(.opacity)

            // The brand mark is HOISTED out of the per-step crossfade (owner
            // 2026-06-16): drawn once, it stays mounted across every brand-mark
            // step, so it never fades/flashes when the text swaps — only the words
            // and buttons crossfade beneath it. Each step reserves its space with a
            // hidden copy. It fades only when entering/leaving the chapter (i.e. the
            // Failure step, which has no mark).
            if showsBrandMark {
                IntroBrandMark()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: vm.step)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Every onboarding step carries the brand mark except the Failure escape-hatch.
    private var showsBrandMark: Bool {
        if case .failure = vm.step { return false }
        return true
    }

    @ViewBuilder
    private var stepView: some View {
        switch vm.step {
        case .welcome:        WelcomeStep()
        case .restoreEntry:   RestoreEntryStep()
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

// MARK: - Intro chapter (shared brand mark)

// `IntroBrandMark` now lives in its own file (IntroBrandMark.swift) so the
// app-entry `LockView` can reuse the exact same mark + position (D-042). It is
// drawn ONCE here, hoisted above the per-step crossfade in `OnboardingView`, so it
// never fades between screens; each step reserves its space with a hidden copy and
// only the splash draws its own via `IntroChapterScaffold(drawsBrandMark: true)`.

/// Layout shared by the centred intro screens (Welcome · Storage · Local warning ·
/// Complete) and the launch splash. Places `IntroBrandMark` at the top (the mark
/// carries its own safe-area top inset, so its Y is identical everywhere), then lets
/// each screen fill the region beneath it. Because the mark sits at the same
/// position on every screen, the per-step crossfade in `OnboardingView` leaves it
/// visually static — the surface feels continuous and only the content and buttons
/// change. The denser Reveal/Confirm screens don't use this scaffold (their content
/// scrolls), but they embed the SAME `IntroBrandMark` at the top of their scroll so
/// the mark lines up and the effect carries through the whole happy path (owner
/// 2026-06-15 — the mark now persists Welcome → Complete rather than fading at the
/// privacy-phrase screens). Only the Failure escape-hatch omits the mark.
private struct IntroChapterScaffold<Content: View, Bottom: View>: View {
    /// Whether THIS scaffold paints the brand mark. The splash (RootView) does; the
    /// onboarding steps don't — there the mark is hoisted above the per-step
    /// crossfade in `OnboardingView`, and the scaffold just RESERVES its space with
    /// a hidden copy so the content still sits below it.
    var drawsBrandMark: Bool = false
    @ViewBuilder var content: () -> Content
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        StepScaffold {
            VStack(spacing: 0) {
                IntroBrandMark()
                    .opacity(drawsBrandMark ? 1 : 0)
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } bottom: {
            bottom()
        }
    }
}

// Onboarding buttons use the shared dock-geometry pills (DockPillRow.swift) —
// owner decision 2026-06-12 (HiFi v1.11.1): a single pill sits exactly over
// the four dock-button slots; pairs split into slots 1+2 / 3+4.

/// A NON-interactive footer styled as a subtle outline dock pill — used on the
/// splash, in the CTA's slot, to carry the copyright (owner 2026-06-16: a pill
/// design, not a button; muted so it reads as a footer rather than a tappable CTA).
private struct SplashFooterPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(CatchlightFont.ui(.medium, size: 15, relativeTo: .body))   // button-label style
            .foregroundStyle(Color.ckTextSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().strokeBorder(Color.ckTextSecondary.opacity(0.3), lineWidth: 1))
            .accessibilityElement()
            .accessibilityLabel(text)
    }
}

// MARK: - Screen 1: Welcome

private struct WelcomeStep: View {
    @Environment(OnboardingViewModel.self) private var vm

    var body: some View {
        WelcomeContent(mode: .welcome, onPrimary: { vm.beginStorageChoice() },
                       onSecondary: { vm.beginRestore() })
    }
}

/// Shared layout behind BOTH the launch splash and the onboarding Welcome screen
/// (owner 2026-06-14: the splash should look like the first screen with only the
/// text swapped). Both modes use `IntroChapterScaffold`, so the brand mark sits at
/// the same position as on every intro screen; the splash lays out the
/// (invisible) headline / body / button purely to reserve their height. The
/// splash→Welcome crossfade therefore reads as "the brand stays, the words
/// change". Used by `RootView` for the splash (`.splash`, no view model) and by
/// `WelcomeStep` (`.welcome`).
struct WelcomeContent: View {
    enum Mode { case splash, welcome }
    let mode: Mode
    var onPrimary: () -> Void = {}
    /// Welcome only — "I already use Catchlight" (restore an existing phrase). D-087.
    var onSecondary: () -> Void = {}

    private var isWelcome: Bool { mode == .welcome }

    var body: some View {
        // The splash (`.splash`, shown by RootView) paints the brand mark itself; the
        // Welcome step (`.welcome`) reserves the space and lets OnboardingView's
        // hoisted, non-fading mark draw it.
        IntroChapterScaffold(drawsBrandMark: !isWelcome) {
            VStack(spacing: 0) {
                // Pin the hero line at the shared set position (every brand-mark
                // screen uses `introHeroTopGap`); the body then settles toward the
                // button via the flexible spacer.
                Spacer().frame(height: introHeroTopGap)
                // Primary-text slot. The headline is laid out in BOTH modes (so the
                // slot keeps the same height); the splash hides it and overlays the
                // tagline in its place.
                ZStack {
                    headline.opacity(isWelcome ? 1 : 0)
                    if !isWelcome { tagline }
                }
                Spacer(minLength: 24)
                bodyBlock.opacity(isWelcome ? 1 : 0)
                Spacer().frame(height: 24)
            }
        } bottom: {
            // Welcome shows the CTA; the splash fills the SAME toolbar slot with a
            // non-interactive © footer styled as a subtle outline pill (owner
            // 2026-06-16) — keeps the splash's bottom edge anchored like the others.
            if isWelcome {
                VStack(spacing: 12) {
                    // Secondary path (owner 2026-07-02, D-087): adopt an existing identity by
                    // entering its phrase — styled as a link in ckTextObie (the Restore token).
                    Button(action: onSecondary) {
                        Text("I already use Catchlight")
                            .font(CatchlightFont.ui(.medium, size: 15, relativeTo: .body))
                            .foregroundStyle(Color.ckTextObie)
                    }
                    .accessibilityIdentifier("onboarding-restore-link")
                    DockPillRow {
                        DockPill(title: "Create my privacy phrase", action: onPrimary)
                    }
                }
            } else {
                DockPillRow {
                    SplashFooterPill(text: "© 2026 Considus")
                }
            }
        }
    }

    private var headline: some View {
        Text("You don't need to choose privacy, it's yours and you never have to ask for it.")
            .font(CatchlightFont.displayFixed(size: 28))
            .foregroundStyle(Color.ckTextPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    /// The brand tagline (same line as the launch-screen composite), shown only on
    /// the splash, occupying the headline slot.
    private var tagline: some View {
        Text("Every thought deserves a moment of clarity.")
            // Fixed 28 to match every onboarding headline (owner 2026-06-29: all
            // intro hero lines are now `displayFixed(28)`, static — so the splash
            // tagline and the Welcome headline it crossfades into are pixel-matched).
            // The secondary colour + italic keep it reading as a tagline.
            .font(CatchlightFont.displayFixed(size: 28))
            .foregroundStyle(Color.ckTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    private var bodyBlock: some View {
        VStack(spacing: 16) {
            (Text("First, we'll create your privacy phrase — 12 words that are the ")
             + Text("ONLY").bold()
             + Text(" key to your data."))
                .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                .foregroundStyle(Color.ckTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("We never see them, store them, or ask for them. So don't lose them.")
                .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                .foregroundStyle(Color.ckTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Restore: "I already use Catchlight" — enter an existing phrase (D-087)

private struct RestoreEntryStep: View {
    @Environment(OnboardingViewModel.self) private var vm
    /// Twelve discrete word fields (owner 2026-07-02, option B): explicit positions, sturdy
    /// for a once-a-year action, and no per-word validity signal (correctness is a whole-
    /// phrase check on Restore — matching onboarding's "reveal nothing granular" posture).
    @State private var fields: [String] = Array(repeating: "", count: 12)

    private var words: [String] {
        fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    }
    private var filledCount: Int { words.filter { !$0.isEmpty }.count }
    private var ready: Bool { filledCount == 12 }

    var body: some View {
        StepScaffold {
            ScrollView {
                VStack(spacing: 0) {
                    // Reserve the hoisted brand mark's space (hidden copy) — as Reveal/Confirm.
                    IntroBrandMark().opacity(0)

                    Spacer().frame(height: introHeroTopGap)
                    Text("Enter your privacy phrase")
                        .font(CatchlightFont.displayFixed(size: 28))
                        .foregroundStyle(Color.ckTextPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Spacer().frame(height: 16)
                    Text("The 12 words from your other device, in order.")
                        .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                        .foregroundStyle(Color.ckTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer().frame(height: 24)
                    PhraseEntryGrid(fields: $fields, onEdit: { vm.clearRestoreError() })
                    Spacer().frame(height: 14)
                    statusLine
                    Spacer(minLength: 24)
                }
            }
        } bottom: {
            DockPillRow(primary: {
                DockPill(title: "Restore") { vm.submitRestore(words) }
                    .disabled(!ready)
                    .opacity(ready ? 1 : 0.5)
            }, trailing: {
                DockPill(title: "Back", secondary: true) { vm.cancelRestore() }
            })
        }
    }

    private var statusLine: some View {
        let message: String
        let isError: Bool
        if let err = vm.restoreError { message = err; isError = true }
        else if ready { message = "Ready to restore."; isError = false }
        else { message = "\(filledCount) of 12 words"; isError = false }
        return Text(message)
            .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .caption))
            .foregroundStyle(isError ? Color.ckRuby : Color.ckTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Screen 2: Storage choice

private struct StorageChoiceStep: View {
    @Environment(OnboardingViewModel.self) private var vm

    var body: some View {
        IntroChapterScaffold {
            VStack(spacing: 0) {
                // Hero line at the shared set position.
                Spacer().frame(height: introHeroTopGap)
                Text("Now, where should your Takes live?")
                    .font(CatchlightFont.displayFixed(size: 28))
                    .foregroundStyle(Color.ckTextPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                // PARTIAL mirror of the brand→hero gap (owner 2026-06-16 "middle
                // ground"): a full mirror dropped the Cloud panel below the pill line
                // once the 16pt descriptions grew the cards (the Cloud one wraps to 3
                // lines). Eased to 48 — more than the old 32, but kept conservative so
                // the Cloud panel stays above the pill line even when the hero wraps.
                Spacer().frame(height: 48)

                VStack(spacing: 16) {
                    StorageOptionCard(
                        title: "Local — on this device only",
                        description: "Your Takes stay on this device. If you lose it without a backup, they're gone."
                    ) { vm.chooseStorage(.local) }

                    StorageOptionCard(
                        title: "Cloud — backed up and restorable",
                        description: "Connect a cloud folder you control. Your Takes remain encrypted — we never see them."
                    ) { vm.chooseStorage(.cloud) }
                }

                Spacer(minLength: 24)
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
                    // Matches every onboarding subtext (owner 2026-06-16: unified at
                    // 16 light Secondary everywhere; this panel text was 14 regular).
                    .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
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
        IntroChapterScaffold {
            VStack(spacing: 0) {
                // Hero line at the shared set position; the warning paragraph then
                // drops to the LOW subtext position — the same placement as the
                // Welcome body block — so the two screens read consistently as they
                // crossfade (owner 2026-06-15: "One thing before…" should match the
                // low subtext of "You don't need to choose…"). A flexible spacer
                // carries it down toward the dock while the hero stays pinned.
                Spacer().frame(height: introHeroTopGap)
                Text("One thing before we continue.")
                    .font(CatchlightFont.displayFixed(size: 28))
                    .foregroundStyle(Color.ckTextPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 24)
                Text("Without cloud backup, your Takes exist only on this device. If you lose access to it and haven't set up a second device, your data cannot be recovered.")
                    .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                    .foregroundStyle(Color.ckTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 24)
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
                VStack(spacing: 0) {
                    // Reserve the brand-mark space (owner 2026-06-15); the visible,
                    // non-fading mark is hoisted in OnboardingView so it doesn't flash
                    // between steps. `.opacity(0)` keeps the same Y/height here.
                    IntroBrandMark()
                        .opacity(0)
                    // Hero line at the shared set position (consistent with the
                    // IntroChapterScaffold screens).
                    Spacer().frame(height: introHeroTopGap)

                    VStack(spacing: 20) {
                        Text("Your privacy phrase")
                            .font(CatchlightFont.displayFixed(size: 28))
                            .foregroundStyle(Color.ckTextPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        // The words lead, directly under the hero; the "write these
                        // down" instruction follows BELOW the grid (owner 2026-06-15)
                        // so it lands in the low subtext position shared with Welcome
                        // and Local-warning.
                        wordGrid(words: vm.mnemonic)
                            .padding(.top, 4)

                        // ckTextSecondary, matching the confirm prompt (owner
                        // 2026-06-12, HiFi v1.11.5 — the amber treatment retired).
                        Text(bodyText)
                            .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                            .foregroundStyle(Color.ckTextSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // No manual bottom clearance: the `safeAreaInset(.bottom)` dock
                // already insets the scroll content above the pinned pill. The old
                // 100pt padding doubled that up and made the content taller than the
                // viewport — forcing a scroll even when everything fit (owner
                // 2026-06-15). The dock's own fade carries the soft bottom edge.
            }
            // Don't rubber-band when the content already fits (owner 2026-06-15):
            // `.basedOnSize` lets the scroll view bounce only if content actually
            // exceeds the viewport (e.g. accessibility text sizes), so at default
            // sizes the screen sits truly static.
            .scrollBounceBehavior(.basedOnSize)
        } bottom: {
            DockPillRow {
                DockPill(title: "I've written them down") { vm.proceedToConfirm() }
            }
        }
    }

    private func wordGrid(words: [String]) -> some View {
        // 3×4 (owner 2026-06-15): three columns pack the 12 words into four rows
        // instead of six and remove the wide trailing gap the 2-column cards left
        // after each word — tighter on the page and quicker to scan.
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                HStack(spacing: 5) {
                    Text("\(idx + 1)")
                        .font(CatchlightFont.ui(.regular, size: 12, relativeTo: .caption))
                        .foregroundStyle(Color.ckTextSecondary)
                    Text(word)
                        // The 12 words use the subtext font, not Cormorant (owner
                        // 2026-06-16): DS §2.1 reserves Cormorant for display moments,
                        // never functional content; sans is also clearer for a phrase
                        // you must transcribe exactly.
                        .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                        .foregroundStyle(Color.ckTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
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
                VStack(spacing: 0) {
                    // Reserve the brand-mark space (hoisted + non-fading, as Reveal).
                    IntroBrandMark()
                        .opacity(0)
                    // The gap to the hero now also HOSTS the validation message: it
                    // floats as a card centred between the brand mark and the hero
                    // (owner 2026-06-15). Previously the error reserved a line down in
                    // the flow, between the slots and the bank — that extra height
                    // pushed the bottom bank row under the dock fade. Floating it here
                    // keeps the slots + bank tight and fully on-screen, and a wrong
                    // guess never shifts the layout (the card is an overlay, so the
                    // hero stays pinned at the set position whether or not it shows).
                    // ckTextObie, not ckEmber: Ember fails WCAG AA on Paper at 13pt
                    // (DS §12.3); resolves to Ember Text #856539 Daylight / Glow Night.
                    Color.clear
                        .frame(height: introHeroTopGap)
                        .overlay {
                            if let failure = vm.failure {
                                Text(failure)
                                    .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .caption))
                                    .foregroundStyle(Color.ckTextObie)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.ckEmber.opacity(0.12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .strokeBorder(Color.ckEmber.opacity(0.35), lineWidth: 1)
                                            )
                                    )
                                    .padding(.horizontal, 24)
                                    // Nudge to the VISUAL centre of the wordmark→hero
                                    // gap: the geometric centre reads a touch high
                                    // because the Cormorant hero sits low in its line
                                    // box (owner 2026-06-15).
                                    .offset(y: 16)
                                    .transition(.opacity)
                                    .accessibilityLabel(failure)
                            }
                        }
                        .animation(.easeInOut(duration: 0.18), value: vm.failure)

                    VStack(spacing: 12) {
                        Text("Confirm three words")
                            .font(CatchlightFont.displayFixed(size: 28))
                            .foregroundStyle(Color.ckTextPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        Text(promptCopy)
                            .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                            .foregroundStyle(Color.ckTextSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        // Slots + bank read as one block: the gap between the to-fill
                        // row and the word bank matches the gap between the bank's own
                        // rows (10), so the cells feel like a single family (owner
                        // 2026-06-15). This also recovers the height that was nudging
                        // the bottom row under the dock fade.
                        VStack(spacing: 10) {
                            slotsRow
                            bankGrid
                        }
                    }
                }
                // As Reveal: no manual bottom clearance — the dock's
                // `safeAreaInset` already insets the scroll content (owner
                // 2026-06-15). Avoids the phantom over-scroll.
            }
            // As Reveal: bounce only when content actually overflows.
            .scrollBounceBehavior(.basedOnSize)
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
        // Slots match the bank tiles below — same 44pt height, same 10pt gutters
        // (owner 2026-06-15): they read as one family of cells and the row no longer
        // costs the extra height that pushed the bank off-screen.
        HStack(spacing: 10) {
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
                    // Number INLINE, to the left of the word — same arrangement as
                    // the reveal cells (owner 2026-06-15), so the slot reads as a
                    // single-line cell rather than a taller stacked one. The position
                    // number stays the small grey prefix; the word fills the rest.
                    HStack(spacing: 5) {
                        Text(positionLabel)
                            .font(CatchlightFont.ui(.regular, size: 12, relativeTo: .caption))
                            .foregroundStyle(Color.ckTextSecondary)
                        Text(value ?? "—")
                            .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))   // 12 words → subtext font (DS §2.1; Confirm bank is interactive)
                            .foregroundStyle(value == nil ? Color.ckTextSecondary : Color.ckTextPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
                .frame(minHeight: 44)
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
        // 3×4 — matches the reveal grid (owner 2026-06-15: both phrase grids moved
        // 2×6 → 3×4 to compact the cards), order preserved from the shuffle.
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        return LazyVGrid(columns: columns, spacing: 10) {
            // Index-based identity + usage (2026-06-10): tracking by word value
            // greyed BOTH tiles when a phrase contained a duplicate word, and
            // could make the confirm step unwinnable.
            ForEach(Array(vm.bank.enumerated()), id: \.offset) { index, word in
                let used = vm.usedBankIndices.contains(index)
                Button { vm.tapBankWord(at: index) } label: {
                    Text(word)
                        .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))   // 12 words → subtext font (DS §2.1; Confirm bank is interactive)
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

    /// The encryption-fact line that follows the voice gem — storage-specific.
    /// The cloud line is a POINTER, not a claim (2026-07-01): nothing in
    /// onboarding configures a cloud folder, so the previous "backed up to your
    /// cloud folder" copy was factually wrong at the moment it was shown —
    /// backup starts only after the user picks a folder in Settings. Sync mode
    /// already defaults to Automatic, so the folder pick is the only step left.
    private var bodyText: String {
        switch vm.storagePath {
        case .local:
            return "Encrypted on this device, readable only by you."
        case .cloud:
            return "Encrypted on this device, readable only by you. To finish setting up cloud backup, choose your folder in Settings → System → Cloud Storage."
        }
    }

    var body: some View {
        // Carry the persistent brand mark through to the end (owner 2026-06-15):
        // the icon+wordmark sits at the same Y as every other intro screen, so the
        // standalone 72pt hero icon is retired in favour of the shared mark.
        IntroChapterScaffold {
            VStack(spacing: 0) {
                // Hero line at the shared set position (was centred — owner
                // 2026-06-16: keep "You're ready." consistent with every other
                // brand-mark screen).
                Spacer().frame(height: introHeroTopGap)
                Text("You're ready.")
                    .font(CatchlightFont.displayFixed(size: 28))
                    .foregroundStyle(Color.ckTextPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                // The voice gem + encryption fact drop to the LOW subtext position
                // (owner 2026-06-15) — same placement as Welcome / Local-warning, so
                // the closing screen shares the rhythm. A flexible spacer carries the
                // block down toward the dock; the hero stays pinned. The gem leads in
                // Primary (the "story before the real app opens"), then the
                // storage-specific encryption fact in Secondary; both 16 light, like
                // every other onboarding subtext.
                Spacer(minLength: 24)
                VStack(spacing: 12) {
                    Text("Your thoughts, in your order, telling your story. Nobody else's.")
                        .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                        .foregroundStyle(Color.ckTextPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(bodyText)
                        .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                        .foregroundStyle(Color.ckTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer().frame(height: 24)
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
                    .font(CatchlightFont.displayFixed(size: 28))
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
                    .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
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
    let vm = OnboardingViewModel(onComplete: { _, _ in })
    return OnboardingView()
        .environment(vm)
        .preferredColorScheme(.dark)
}

#Preview("Onboarding — reveal (Night)") {
    let vm = OnboardingViewModel(onComplete: { _, _ in })
    vm.beginStorageChoice()
    vm.chooseStorage(.cloud)
    return OnboardingView()
        .environment(vm)
        .preferredColorScheme(.dark)
}

#Preview("Onboarding — confirm (Daylight)") {
    let vm = OnboardingViewModel(onComplete: { _, _ in })
    vm.beginStorageChoice()
    vm.chooseStorage(.cloud)
    vm.proceedToConfirm()
    return OnboardingView()
        .environment(vm)
        .preferredColorScheme(.light)
}
