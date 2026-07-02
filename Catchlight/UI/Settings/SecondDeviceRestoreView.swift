//
//  SecondDeviceRestoreView.swift
//  Catchlight (iOS app target) — Settings → Second device (D-087)
//
//  The Settings entry point for cross-device restore: re-key THIS device to the
//  account behind a privacy phrase. Reached only after the user confirms the
//  destructive warning on the Security row (see SettingsView). Because an onboarded
//  device already holds Takes under its current key, committing a new phrase wipes
//  this device's local Takes before re-binding — so the screen restates that here,
//  and the actual wipe/re-key is `AppModel.replaceAccountForSecondDevice`.
//
//  The 12-field entry reuses `PhraseEntryGrid`, the same component the onboarding
//  restore branch uses, so phrase entry behaves identically in both places.
//

import SwiftUI

struct SecondDeviceRestoreView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var fields: [String] = Array(repeating: "", count: 12)
    @State private var errorText: String?

    private var words: [String] {
        fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    }
    private var filledCount: Int { words.filter { !$0.isEmpty }.count }
    private var ready: Bool { filledCount == 12 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    warningCard

                    Text("Enter your privacy phrase")
                        .font(CatchlightFont.displayFixed(size: 28))
                        .foregroundStyle(Color.ckTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityAddTraits(.isHeader)

                    Text("The 12 words from your other device, in order.")
                        .font(CatchlightFont.ui(.light, size: 16, relativeTo: .body))
                        .foregroundStyle(Color.ckTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .fixedSize(horizontal: false, vertical: true)

                    PhraseEntryGrid(fields: $fields, onEdit: { errorText = nil })

                    statusLine

                    restoreButton
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.ckBackground)
            .navigationTitle("Second device")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
    }

    /// Restates the destructive consequence at the point of action (the Security row
    /// already warned once). Ruby-toned, matching the app's "state precedence" accent.
    private var warningCard: some View {
        Text("This replaces the account on this device. Takes stored only here will be removed and can't be recovered — if you haven't already, close this and use Export Takes (Markdown) to keep a copy first.")
            .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .footnote))
            .foregroundStyle(Color.ckRuby)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.ckRuby.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.ckRuby.opacity(0.35), lineWidth: 1))
    }

    private var statusLine: some View {
        let message: String
        let isError: Bool
        if let errorText { message = errorText; isError = true }
        else if ready { message = "Ready to restore."; isError = false }
        else { message = "\(filledCount) of 12 words"; isError = false }
        return Text(message)
            .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .caption))
            .foregroundStyle(isError ? Color.ckRuby : Color.ckTextSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var restoreButton: some View {
        Button(action: submit) {
            Text("Restore on this device")
                .font(CatchlightFont.ui(.medium, size: 15, relativeTo: .body))
                .foregroundStyle(Color.ckOnAccent)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(Color.ckEmber))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .opacity(ready ? 1 : 0.5)
        .accessibilityIdentifier("second-device-restore")
    }

    private func submit() {
        if let error = app.replaceAccountForSecondDevice(words) {
            errorText = error            // bad phrase / device fault — nothing destroyed on a bad phrase
        } else {
            // Success: the app has re-keyed and now shows the connect-folder guidance
            // on the timeline. Close this sheet AND the Settings sheet behind it.
            dismiss()
            app.ui.isSettingsPresented = false
        }
    }
}
