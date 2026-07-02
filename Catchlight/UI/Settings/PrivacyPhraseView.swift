//
//  PrivacyPhraseView.swift
//  Catchlight (iOS app target) — Task 3.12
//
//  Settings → Security → Privacy phrase.
//
//  The 12-word BIP-39 mnemonic is the user's only recovery path. We treat its
//  re-display as security-sensitive. The real gate is the device's own
//  `.userPresence` auth (Face ID / passcode), which `MnemonicKeychain.retrieve()`
//  forces on every read — so an unlocked app is NEVER enough to reveal the phrase
//  (D-042):
//    1. The fresh iOS auth alone gates the reveal (the in-app PIN was REMOVED
//       by D-042; this comment previously described it — corrected 2026-07-01).
//    2. The phrase only loads after MnemonicKeychain's iOS prompt.
//    3. Words appear in a numbered 3-column grid, blurred by default.
//       "Press and hold to reveal" — the `LongPressGesture(minimumDuration: 0)`
//       with `.updating(_:body:)` fires on press, releases on lift, so it is
//       NOT a tap. Words blur again as soon as the finger leaves.
//

import SwiftUI

@MainActor
struct PrivacyPhraseView: View {

    @Environment(\.dismiss) private var dismiss

    private enum Stage: Equatable {
        case authenticate       // reveal gated by the device's `.userPresence` auth
        case missingPhrase      // mnemonic was never persisted (legacy install / other device)
        case revealed([String]) // 12 words, ready to display blurred
    }

    @State private var stage: Stage
    @State private var errorText: String?

    init() {
        // The reveal is gated solely by the fresh iOS auth that MnemonicKeychain
        // forces (D-042 — the in-app PIN was removed). Either the phrase exists and
        // we authenticate to show it, or it was never persisted on this device.
        _stage = State(initialValue: MnemonicKeychain.exists() ? .authenticate : .missingPhrase)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Privacy Phrase")
                .navigationBarTitleDisplayMode(.inline)
                // No Done button — dismiss by swiping down (owner 2026-06-29),
                // matching About / Cloud Storage. The drag indicator shows it.
                .background(Color.ckBackground.ignoresSafeArea())
        }
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .authenticate:
            authenticatePrompt
        case .missingPhrase:
            explainer(
                symbol: "questionmark.key.filled",
                title: "Phrase isn't on this device",
                body: "Catchlight stores the privacy phrase only on the device where you set it up. If you onboarded on a different device, use that one to view it."
            )
        case .revealed(let words):
            revealGrid(words: words)
        }
    }

    // MARK: - Authenticate (no in-app PIN)

    /// No in-app PIN set: the reveal is gated solely by the fresh iOS auth that
    /// `MnemonicKeychain.retrieve()` forces. An explicit tap triggers it — we never
    /// auto-read the crown-jewels on appear.
    private var authenticatePrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "faceid")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Color.ckAccent)
            Text("Reveal your privacy phrase")
                .font(CatchlightFont.displayFixed(size: 28))
                .foregroundStyle(Color.ckTextPrimary)
                .multilineTextAlignment(.center)
            Text("Authenticate with Face ID or your device passcode to view the 12 words — they're the only way to recover your account, so reveal them somewhere private.")
                .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .subheadline))
                .foregroundStyle(Color.ckTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let errorText {
                Text(errorText)
                    .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .caption))
                    .foregroundStyle(Color.ckTextObie)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ckBackground)
        .safeAreaInset(edge: .bottom) {
            DockPillRow {
                DockPill(title: "Reveal phrase") { revealViaDeviceAuth() }
            }
            .dockFadeBackground()
        }
    }

    private func revealViaDeviceAuth() {
        // MnemonicKeychain.retrieve() forces the iOS `.userPresence` prompt and
        // returns nil on cancel/failure. `exists()` was true at init, so nil here
        // means the auth was dismissed — not a missing phrase.
        if let words = MnemonicKeychain.retrieve(), words.count == 12 {
            stage = .revealed(words)
            errorText = nil
        } else {
            errorText = "Authentication needed to reveal your phrase."
        }
    }

    // MARK: - Reveal grid

    private func revealGrid(words: [String]) -> some View {
        PhraseRevealGrid(words: words)
    }

    private func explainer(symbol: String, title: String, body: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Color.ckAccent)
            Text(title)
                .font(CatchlightFont.displayFixed(size: 28))
                .foregroundStyle(Color.ckTextPrimary)
                .multilineTextAlignment(.center)
            Text(body)
                .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .subheadline))
                .foregroundStyle(Color.ckTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ckBackground)
    }
}

// MARK: - Hold-to-reveal grid

@MainActor
private struct PhraseRevealGrid: View {
    let words: [String]
    @GestureState private var isHeld: Bool = false
    /// VoiceOver-driven toggle. Press-and-hold isn't a usable gesture under VO
    /// (VO intercepts long press), so when VO is on we expose Reveal / Hide as
    /// named accessibility actions and track the latched state here.
    @State private var voRevealed: Bool = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    /// Effective reveal state — either the user is physically holding, or VO has
    /// latched the reveal on via its named action.
    private var revealed: Bool { isHeld || voRevealed }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(spacing: 24) {
            Text("Write these 12 words down somewhere safe. They are the only way to recover your account.")
                .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .subheadline))
                .foregroundStyle(Color.ckTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    wordCell(index: index, word: word)
                }
            }
            .padding(.horizontal, 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(revealed
                ? "Phrase revealed: \(words.joined(separator: ", "))"
                : "Phrase hidden. Press and hold the reveal button to view.")

            Spacer()
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ckBackground)
        // Dock-geometry position for the hold control (D-022 button system,
        // applied to Settings sub-screens 2026-06-12).
        .safeAreaInset(edge: .bottom) {
            DockPillRow { holdButton }
                .dockFadeBackground()
        }
    }

    private func wordCell(index: Int, word: String) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .caption))
                .foregroundStyle(Color.ckTextSecondary)
                .frame(width: 22, alignment: .trailing)
            Text(word)
                .font(CatchlightFont.ui(.medium, size: 15, relativeTo: .body))
                .foregroundStyle(Color.ckTextPrimary)
                .blur(radius: revealed ? 0 : 7)
                .animation(.easeInOut(duration: 0.12), value: revealed)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.ckSurface)
                .daylightCardShadow()   // DS §4.1 — same lift as the onboarding chips
        )
    }

    private var holdButton: some View {
        Text(revealed ? "Release to hide" : "Hold to reveal")
            .font(CatchlightFont.ui(.medium, size: 15, relativeTo: .body))
            // Ink in BOTH modes (deliberate deviation from the pill system's
            // ckBackground label): the revealed state fills with GLOW, and
            // Paper-on-Glow is illegible in Daylight — Ink reads on both fills.
            .foregroundStyle(Color.ckInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule().fill(revealed ? Color.ckGlow : Color.ckEmber)
            )
            .contentShape(Capsule())
            // LongPressGesture with minimumDuration: 0 fires on press and updates
            // GestureState to true; the binding flips back to false the moment the
            // gesture ends. This gives us a true "hold to reveal" — not a tap toggle.
            //
            // Under VoiceOver this gesture is unreachable (VO intercepts long press),
            // so we ALSO expose named accessibility actions below that latch the
            // reveal on/off until the user dismisses it. This means the words DO
            // stay on screen for a VO user — which is the only way they can read
            // them out. The reveal is gated by PIN entry upstream, so this doesn't
            // weaken the security model — it just makes the words actually accessible.
            .gesture(
                LongPressGesture(minimumDuration: 0)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .updating($isHeld) { value, state, _ in
                        switch value {
                        case .first: state = true
                        case .second(true, _): state = true
                        default: state = false
                        }
                    }
            )
            .accessibilityLabel(voiceOverEnabled
                                ? (voRevealed ? "Hide phrase" : "Reveal phrase")
                                : "Hold to reveal phrase")
            .accessibilityHint(voiceOverEnabled
                               ? "Double-tap to toggle the phrase on screen."
                               : "Press and hold to display the 12 words. Release to hide them.")
            .accessibilityAction(named: voRevealed ? "Hide phrase" : "Reveal phrase") {
                voRevealed.toggle()
            }
    }
}
