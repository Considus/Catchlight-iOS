//
//  PINEntryView.swift
//  Catchlight (iOS app target) — Task 3.12
//
//  Reusable numeric PIN entry. Used in two places:
//    • PINSetupView — create / confirm a new PIN.
//    • PrivacyPhraseView — gate the phrase reveal behind the existing PIN.
//
//  Behaviour is intentionally minimal:
//    • Shows `length` slot pips, fills them as the user types.
//    • Restricts input to digits.
//    • Fires `onSubmit` when the user enters the configured length.
//    • Displays an optional error banner.
//
//  Storage and verification stay in PINService — this view is presentation only.
//

import SwiftUI

@MainActor
struct PINEntryView: View {

    let title: String
    let subtitle: String
    /// Expected number of digits. Defaults to the spec's 6-digit PIN.
    var length: Int = 6
    /// Called with the entered PIN once it reaches `length`. The parent decides
    /// what to do (verify, advance to confirm, etc.) and may set `errorText`.
    var onSubmit: (String) -> Void
    var errorText: String? = nil

    @State private var pin: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text(title)
                    .font(CatchlightFont.ui(.regular, size: 22, relativeTo: .title3))
                    .foregroundStyle(Color.ckTextPrimary)
                Text(subtitle)
                    .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .subheadline))
                    .foregroundStyle(Color.ckTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            pips

            if let errorText {
                Text(errorText)
                    .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .footnote))
                    .foregroundStyle(Color.ckRuby)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Hidden field captures the keyboard. Tapping anywhere refocuses it.
            TextField("", text: Binding(
                get: { pin },
                set: { newValue in
                    let digits = newValue.filter(\.isNumber).prefix(length)
                    pin = String(digits)
                    if pin.count == length {
                        let submitted = pin
                        onSubmit(submitted)
                    }
                }
            ))
            .keyboardType(.numberPad)
            // No content type: `.oneTimeCode` actively INVITES SMS-code autofill
            // suggestions on recent iOS — the opposite of suppressing chrome for
            // a secret PIN. `.numberPad` already has no predictive bar.
            .textContentType(nil)
            .focused($fieldFocused)
            .frame(width: 0, height: 0)
            .opacity(0.001)
            .accessibilityLabel("Passcode digits")

            Spacer(minLength: 0)
        }
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ckBackground)
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
        .onAppear { fieldFocused = true }
    }

    private var pips: some View {
        HStack(spacing: 16) {
            ForEach(0..<length, id: \.self) { idx in
                Circle()
                    .strokeBorder(Color.ckTextSecondary, lineWidth: 1.5)
                    .background(
                        Circle().fill(idx < pin.count ? Color.ckTextPrimary : Color.clear)
                    )
                    .frame(width: 18, height: 18)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pin.count) of \(length) digits entered")
    }
}
