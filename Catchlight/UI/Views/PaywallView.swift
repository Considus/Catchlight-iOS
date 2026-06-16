//
//  PaywallView.swift
//  Catchlight (iOS app target) — Task 6.20
//
//  Fully custom paywall. We deliberately do NOT use `SubscriptionStoreView`
//  because:
//    1. It can't be styled to the Catchlight design system without surfaces
//       breaking out of the theme.
//    2. The product needs Cormorant Garamond italic in the hero, which only a
//       custom view can do.
//
//  Apple's mandatory paywall elements (otherwise rejection risk):
//    • Price + billing period (live from Product.displayPrice)
//    • Trial duration when applicable
//    • Subscribe CTA
//    • Restore Purchases
//    • Redeem Code  (iOS 16+)
//    • Privacy Policy + Terms of Service links
//    • Subscription terms summary (auto-renews, cancel anytime)
//
//  The paywall is NOT a hard gate. The dismiss control is always available;
//  the app continues in `.lapsed` read-only mode (view + reminders + export).
//

import SwiftUI
import CatchlightCore
import StoreKit

struct PaywallView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    // D-030 (+ owner refinement: Default is the floor). The subscribe CTA is not
    // a DockPill but shares the dock geometry, so it mirrors the same rule:
    // above the default text size the label grows/wraps instead of shrinking.
    @Environment(\.dynamicTypeSize) private var dynamicSize

    /// Bound to the manager so price / trial copy update reactively as soon
    /// as `loadProduct()` resolves.
    private var manager: SubscriptionManager { app.subscription }

    // Composition per HiFi v1.7 §12 (owner 2026-06-12, internal v1.11.2–.4):
    // everything centred except the terms block (matching the onboarding
    // screens); hero's first line on the standard heading line (top 26);
    // the eyebrow splits the hero↔values space equally; the Cormorant
    // trial/price line bisects the values↔auto-renews space (equal spacers);
    // CTA = the dock-geometry pill pinned at the dock's resting position.
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.ckBackground.ignoresSafeArea()

            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 22) {
                        hero
                        eyebrow
                        valueProps
                        Spacer(minLength: 12)
                        pricingLine
                        Spacer(minLength: 12)
                        renewalCopy
                        secondaryActions
                        legalBlock
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 26)   // standard heading line (HiFi v1.11.3)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    // Fill the viewport so the equal-split Spacers lay out like
                    // the static mock; the view only actually scrolls at
                    // accessibility text sizes.
                    .frame(minHeight: geo.size.height)
                }
                // The sheet marker lives on the ScrollView, NOT the container
                // ZStack (2026-06-10): a container-level accessibilityIdentifier
                // propagates onto every descendant accessibility element on the
                // current SwiftUI runtime, which overwrote the dismiss button's
                // own "paywall-dismiss" identifier and broke the UI tests.
                .accessibilityIdentifier("paywall-sheet")
            }

            dismissButton
        }
        .safeAreaInset(edge: .bottom) {
            // The dock's soft edge (HiFi v1.11.5) — the legal block fades out
            // beneath the CTA zone when the view scrolls at large text sizes.
            DockPillRow { primaryCTA }
                .dockFadeBackground()
        }
        .task {
            await manager.loadProduct()
        }
    }

    // MARK: - Sections

    private var hero: some View {
        Text("A quieter way\nto hold the day.")
            .font(CatchlightFont.displayFixed(size: 38))
            .foregroundStyle(Color.ckTextPrimary)
            .lineSpacing(4)   // ≈ the standard heading's 1.25 line-height (HiFi v1.11.3)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    /// Its own stack row, so the standard spacing sits EQUALLY above and below
    /// (owner 2026-06-12, HiFi v1.11.4).
    private var eyebrow: some View {
        Text("Catchlight Annual")
            .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .footnote))
            .tracking(2)
            .textCase(.uppercase)
            .foregroundStyle(Color.ckTextObie)
    }

    private var valueProps: some View {
        // Centred, bullet-free (owner 2026-06-12, HiFi v1.11.3 — dots aren't
        // used anywhere else in the product).
        VStack(spacing: 12) {
            valueRow("Unlimited Takes, tasks and reminders")
            valueRow("Encrypted cloud sync across your devices")
            valueRow("Your data stays yours — readable, exportable")
        }
    }

    private func valueRow(_ text: String) -> some View {
        Text(text)
            .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
            .foregroundStyle(Color.ckTextPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The trial/price line is a Cormorant Light Italic display moment that
    /// breaks the page up (owner 2026-06-12, HiFi v1.11.3). It bisects the
    /// values↔auto-renews space via the equal Spacers in `body`.
    private var pricingLine: some View {
        Group {
            if manager.isEligibleForIntroOffer, let trial = manager.trialDurationCopy {
                // L10N: composed phrase. `trial` ("14 days") and `priceCopy`
                // ("£14.99/year") are both locale-aware via StoreKit, but the
                // glue copy ("free, then") needs the order to be locale-aware
                // too — e.g. RTL layouts may want the duration last. SwiftUI
                // Text+LocalizedStringKey extracts this as a format string
                // with two %@ args; the future xcstrings will pick it up.
                Text("\(trial) free, then \(priceCopy)")
            } else {
                Text(priceCopy)
            }
        }
        .font(CatchlightFont.display(size: 24, relativeTo: .title3))
        .foregroundStyle(Color.ckTextPrimary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var renewalCopy: some View {
        Text("Auto-renews each year. Cancel anytime in your App Store account.")
            .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .footnote))
            .foregroundStyle(Color.ckTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var priceCopy: String {
        manager.annual.map { "\($0.displayPrice)/year" } ?? "—"
    }

    // MARK: - CTAs

    /// Dock-geometry pill (HiFi v1.11.2): Ember fill, ckOnAccent (Ink) label —
    /// the same button system as onboarding. Ink label both modes (D-028):
    /// Paper-on-Ember fails WCAG in Daylight. Sized by the enclosing DockPillRow.
    private var primaryCTA: some View {
        Button {
            Task {
                let succeeded = await manager.purchase()
                if succeeded { dismiss() }
            }
        } label: {
            HStack {
                if manager.isWorking {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.ckOnAccent)
                } else {
                    Text(ctaText)
                        .font(CatchlightFont.ui(.medium, size: 15, relativeTo: .body))
                        .lineLimit(dynamicSize > .large ? 2 : 1)
                        .minimumScaleFactor(dynamicSize > .large ? 1.0 : 0.75)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity,
                   minHeight: dynamicSize > .large ? CatchlightLayout.minTouchTarget : nil,
                   maxHeight: dynamicSize > .large ? nil : .infinity)
            .foregroundStyle(Color.ckOnAccent)
            .background(Capsule().fill(Color.ckEmber))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(manager.isWorking || manager.annual == nil)
        .accessibilityIdentifier("paywall-subscribe")
    }

    private var ctaText: String {
        // Owner-locked CTA copy (HiFi v1.11.1): "Start your 14-day free trial".
        // The adjectival variant keeps the duration live from StoreKit.
        if manager.isEligibleForIntroOffer, let trial = manager.trialDurationAdjectiveCopy {
            return "Start your \(trial) free trial"
        }
        return manager.annual.map { "Subscribe — \($0.displayPrice)/year" } ?? "Subscribe"
    }

    private var secondaryActions: some View {
        VStack(spacing: 12) {
            if let error = manager.lastError {
                Text(error)
                    .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.ckRuby)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            HStack {
                Button("Restore Purchases") {
                    // A successful restore now confirms itself by dismissing
                    // the paywall (the user is entitled; there is nothing left
                    // to do here). Failure surfaces via `manager.lastError`
                    // above — previously success and failure looked identical.
                    Task { if await manager.restore() { dismiss() } }
                }
                .accessibilityIdentifier("paywall-restore")
                Spacer()
                Button("Redeem Code") {
                    redeemOfferCode()
                }
                .accessibilityIdentifier("paywall-redeem")
            }
            .font(CatchlightFont.ui(.regular, size: 15, relativeTo: .subheadline))
            .foregroundStyle(Color.ckTextObie)
            .disabled(manager.isWorking)
        }
    }

    @MainActor
    private func redeemOfferCode() {
        // iOS 16+ presents the offer-code sheet bound to the active window scene.
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            Task {
                try? await AppStore.presentOfferCodeRedeemSheet(in: scene)
            }
        }
    }

    // The terms block is the one un-centred element (owner: matches the
    // onboarding composition; disclosure reads as a quiet footnote).
    private var legalBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your subscription auto-renews each year unless cancelled at least 24 hours before the period ends. Manage or cancel anytime in your App Store account. Catchlight is end-to-end encrypted — your Takes are never readable by us.")
                .font(CatchlightFont.ui(.regular, size: 12, relativeTo: .footnote))
                .foregroundStyle(Color.ckTextSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Justified like Restore/Redeem: Privacy leading · ToS trailing
            // (owner 2026-06-12, HiFi v1.11.3).
            HStack {
                Link("Privacy Policy",
                     destination: URL(string: "https://catchlight.app/privacy")!)
                Spacer()
                Link("Terms of Service",
                     destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stgvs/")!)
            }
            .font(CatchlightFont.ui(.regular, size: 12, relativeTo: .footnote))
            .foregroundStyle(Color.ckTextObie)
        }
    }

    // MARK: - Dismiss

    private var dismissButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.ckTextSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.top, 12)
        .padding(.trailing, 8)
        .accessibilityLabel("Close paywall")
        .accessibilityIdentifier("paywall-dismiss")
    }
}

#Preview("Paywall — Night") {
    let app = AppModel.preview(store: InMemoryTakeStore(), onboarded: true)
    return PaywallView()
        .environment(app)
        .preferredColorScheme(.dark)
}

#Preview("Paywall — Daylight") {
    let app = AppModel.preview(store: InMemoryTakeStore(), onboarded: true)
    return PaywallView()
        .environment(app)
        .preferredColorScheme(.light)
}
