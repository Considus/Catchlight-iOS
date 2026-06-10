//
//  PrivacyPhraseView.swift
//  Catchlight (iOS app target) — Task 3.12
//
//  Settings → Security → Privacy phrase.
//
//  The 12-word BIP-39 mnemonic is the user's only recovery path. We treat its
//  re-display as security-sensitive:
//    1. The caller must already have a PIN set — if not, this view tells them
//       to set one first (the parent handles routing back to PINSetupView).
//    2. The user must enter the current PIN. Only after PINService.verify
//       succeeds does the phrase load from MnemonicKeychain.
//    3. Words appear in a numbered 3-column grid, blurred by default.
//       "Press and hold to reveal" — the `LongPressGesture(minimumDuration: 0)`
//       with `.updating(_:body:)` fires on press, releases on lift, so it is
//       NOT a tap. Words blur again as soon as the finger leaves.
//

import SwiftUI

@MainActor
struct PrivacyPhraseView: View {

    @Environment(\.dismiss) private var dismiss

    private let pinService = PINService()

    private enum Stage: Equatable {
        case noPIN              // can't reveal until PIN is set
        case enterPIN           // PIN gate
        case missingPhrase      // PIN ok, but mnemonic was never persisted (legacy install)
        case revealed([String]) // 12 words, ready to display blurred
    }

    @State private var stage: Stage
    @State private var errorText: String?
    @State private var entryResetId = UUID()

    init() {
        if !MnemonicKeychain.exists() {
            // Legacy install or no onboarding yet — handled in the body.
            _stage = State(initialValue: .missingPhrase)
        } else if !PINSetupAvailability.hasPIN {
            _stage = State(initialValue: .noPIN)
        } else {
            _stage = State(initialValue: .enterPIN)
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Privacy Phrase")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(Color.ckTextObie)
                    }
                }
                .background(Color.ckBackground.ignoresSafeArea())
        }
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .noPIN:
            explainer(
                symbol: "lock",
                title: "Set a PIN first",
                body: "Your privacy phrase is only revealed after entering your PIN. Open Settings → PIN / biometrics to create one, then come back here."
            )
        case .missingPhrase:
            explainer(
                symbol: "questionmark.key.filled",
                title: "Phrase isn't on this device",
                body: "Catchlight stores the privacy phrase only on the device where you set it up. If you onboarded on a different device, use that one to view it."
            )
        case .enterPIN:
            PINEntryView(
                title: "Enter your PIN",
                subtitle: "Verify your PIN to reveal the 12 words.",
                onSubmit: { pin in
                    do {
                        if try pinService.verify(pin) {
                            if let words = MnemonicKeychain.retrieve(), words.count == 12 {
                                stage = .revealed(words)
                            } else {
                                stage = .missingPhrase
                            }
                            errorText = nil
                        } else {
                            errorText = pinService.isLockedOut
                                ? "Too many wrong attempts. Restart the app and use your privacy phrase."
                                : "Incorrect PIN. Try again."
                            entryResetId = UUID()
                        }
                    } catch {
                        errorText = "Couldn't verify the PIN."
                        entryResetId = UUID()
                    }
                },
                errorText: errorText
            )
            .id(entryResetId)
        case .revealed(let words):
            revealGrid(words: words)
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
                .foregroundStyle(Color.ckEmber)
            Text(title)
                .font(CatchlightFont.ui(.regular, size: 20, relativeTo: .title3))
                .foregroundStyle(Color.ckTextPrimary)
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

/// Cheap proxy used by `PrivacyPhraseView.init` to decide the initial stage
/// without holding a PINService instance at the call site. PINService is
/// pure-Keychain, so this is a one-shot lookup.
private enum PINSetupAvailability {
    static var hasPIN: Bool {
        // PINService.verify throws .notFound if no PIN is set; a cheaper check is
        // to look directly for the salt slot. We mirror PINService internals only
        // here, deliberately keeping the rest of the file off any Keychain detail.
        let service = "com.considus.catchlight"
        let account = "pin-salt"
        let accessGroup = "YTPP9HU9F9.com.considus.catchlight"
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecMatchLimit as String:      kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
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

            holdButton

            Spacer().frame(height: 24)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ckBackground)
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
        )
    }

    private var holdButton: some View {
        Text(revealed ? "Release to hide" : "Hold to reveal")
            .font(CatchlightFont.ui(.medium, size: 16, relativeTo: .body))
            .foregroundStyle(Color.ckInk)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
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
