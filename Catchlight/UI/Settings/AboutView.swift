//
//  AboutView.swift
//  Catchlight (iOS app target) — Task 3.12
//
//  Settings → System → About sheet. Static content:
//    • App name + marketing/build version (from Bundle.main.infoDictionary).
//    • A one-line tagline.
//    • Open-source licences — derived from Package.swift's dependency set.
//      Catchlight currently uses only Apple system frameworks (CryptoKit,
//      LocalAuthentication, SQLite3, etc.), so this section says so honestly
//      rather than padding the list with frameworks Apple ships.
//    • "Made by Considus" line.
//

import SwiftUI

@MainActor
struct AboutView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headline
                    tagline
                    licences
                    madeBy
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.ckBackground)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.ckTextObie)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Catchlight")
                .font(CatchlightFont.displayFixed(size: 36))   // wordmark — brand, fixed
                .foregroundStyle(Color.ckTextPrimary)
            Text(Self.versionString)
                .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .subheadline))
                .foregroundStyle(Color.ckTextSecondary)
        }
    }

    private var tagline: some View {
        Text("Privacy-first notes and reminders.")
            .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
            .foregroundStyle(Color.ckTextPrimary)
    }

    private var licences: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open Source Licences")
                .font(CatchlightFont.ui(.medium, size: 15, relativeTo: .subheadline))
                .foregroundStyle(Color.ckTextSecondary)
                .textCase(.uppercase)
            // The Package.swift dependency set is empty — Catchlight ships with
            // only Apple system frameworks. We state that honestly here so the
            // section never lies about what's in the binary.
            Text("Catchlight uses only Apple system frameworks (CryptoKit, LocalAuthentication, Security, SQLite3). No third-party libraries are bundled.")
                .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .subheadline))
                .foregroundStyle(Color.ckTextPrimary)
            Text("The BIP-39 English wordlist is sourced from the Trezor project and bundled under the MIT licence — see Resources/bip39-english.txt.")
                .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .footnote))
                .foregroundStyle(Color.ckTextSecondary)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.ckSurface)
                .daylightCardShadow()   // DS §4.1
        )
    }

    private var madeBy: some View {
        Text("Made by Considus")
            .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .footnote))
            .foregroundStyle(Color.ckTextSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "Version \(version)" : "Version \(version) (\(build))"
    }
}
