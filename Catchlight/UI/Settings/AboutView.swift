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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    brandMark
                    taglineBlock
                    licences
                    links
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
            // No Done button — dismiss by swiping down, matching the Settings sheet
            // (owner 2026-06-16). VoiceOver dismisses via the two-finger scrub
            // (escape) gesture; the drag indicator shows the swipe affordance.
        }
        .presentationDragIndicator(.visible)
    }

    /// The full brand mark — icon over wordmark — centred, mirroring the onboarding
    /// hero (`IntroBrandMark`). Not that exact view: its `deviceTopInset + 114` offset
    /// is tuned for the full-screen flow, whereas this sits inside a sheet's scroll.
    private var brandMark: some View {
        VStack(spacing: 16) {
            Image("catchlight-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Image("catchlight-wordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 44)
                .accessibilityLabel("Catchlight")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 12)
    }

    /// Tagline with the version directly beneath it, both left-justified (owner
    /// 2026-06-16 — version moved out from under the wordmark to under the tagline).
    private var taglineBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Privacy-first notes and reminders.")
                .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                .foregroundStyle(Color.ckTextPrimary)
            Text(Self.versionString)
                .font(CatchlightFont.ui(.regular, size: 14, relativeTo: .subheadline))
                .foregroundStyle(Color.ckTextSecondary)
        }
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

    /// External links, grouped in one card (matches the licences card). Privacy +
    /// Terms reuse the paywall's URLs; Website is the marketing/guides hub; Support
    /// opens Mail. ⚠️ Support address is a placeholder pending owner confirmation.
    private var links: some View {
        VStack(spacing: 0) {
            linkRow("Privacy Policy", url: "https://catchlight.app/privacy", opensMail: false)
            linkDivider
            linkRow("Terms of Service", url: "https://www.apple.com/legal/internet-services/itunes/dev/stgvs/", opensMail: false)
            linkDivider
            linkRow("Support", url: "mailto:support@catchlight.app", opensMail: true)
            linkDivider
            linkRow("Website", url: "https://catchlight.app", opensMail: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.ckSurface)
                .daylightCardShadow()   // DS §4.1 — matches the licences card
        )
    }

    private func linkRow(_ title: String, url: String, opensMail: Bool) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                Text(title)
                    .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .subheadline))
                    .foregroundStyle(Color.ckTextPrimary)
                Spacer()
                Image(systemName: opensMail ? "envelope" : "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ckAccent)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityHint(opensMail ? "Opens your mail app." : "Opens in your browser.")
    }

    private var linkDivider: some View {
        Divider()
            .background(Color.ckTextSecondary.opacity(0.15))
            .padding(.leading, 16)
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
