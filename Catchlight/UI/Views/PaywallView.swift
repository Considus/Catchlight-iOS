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

    /// Bound to the manager so price / trial copy update reactively as soon
    /// as `loadProduct()` resolves.
    private var manager: SubscriptionManager { app.subscription }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.ckBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    valueProps
                    Spacer(minLength: 8)
                    pricingBlock
                    primaryCTA
                    secondaryActions
                    legalBlock
                }
                .padding(.horizontal, 24)
                .padding(.top, 80)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The sheet marker lives on the ScrollView, NOT the container
            // ZStack (2026-06-10): a container-level accessibilityIdentifier
            // propagates onto every descendant accessibility element on the
            // current SwiftUI runtime, which overwrote the dismiss button's
            // own "paywall-dismiss" identifier and broke the UI tests.
            .accessibilityIdentifier("paywall-sheet")

            dismissButton
        }
        .task {
            await manager.loadProduct()
        }
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A quieter way\nto hold the day.")
                .font(CatchlightFont.displayFixed(size: 38))
                .foregroundStyle(Color.ckTextPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("Catchlight Annual")
                .font(CatchlightFont.ui(.medium, size: 14, relativeTo: .footnote))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(Color.ckTextObie)
        }
    }

    private var valueProps: some View {
        VStack(alignment: .leading, spacing: 14) {
            valueRow("Unlimited Takes, Notes, and Reminders")
            valueRow("Encrypted cloud sync across your devices")
            valueRow("Your data stays yours — readable, exportable")
        }
    }

    private func valueRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle()
                .fill(Color.ckEmber)
                .frame(width: 6, height: 6)
                .offset(y: 6)
                .accessibilityHidden(true)
            Text(text)
                .font(CatchlightFont.ui(.regular, size: 17, relativeTo: .body))
                .foregroundStyle(Color.ckTextPrimary)
        }
    }

    private var pricingBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if manager.isEligibleForIntroOffer, let trial = manager.trialDurationCopy {
                // L10N: composed phrase. `trial` ("14 days") and `priceCopy`
                // ("£14.99/year") are both locale-aware via StoreKit, but the
                // glue copy ("free, then") needs the order to be locale-aware
                // too — e.g. RTL layouts may want the duration last. SwiftUI
                // Text+LocalizedStringKey extracts this as a format string
                // with two %@ args; the future xcstrings will pick it up.
                Text("\(trial) free, then \(priceCopy)")
                    .font(CatchlightFont.ui(.medium, size: 20, relativeTo: .title3))
                    .foregroundStyle(Color.ckTextPrimary)
            } else {
                Text(priceCopy)
                    .font(CatchlightFont.ui(.medium, size: 20, relativeTo: .title3))
                    .foregroundStyle(Color.ckTextPrimary)
            }
            Text("Auto-renews each year. Cancel anytime in your App Store account.")
                .font(CatchlightFont.ui(.regular, size: 13, relativeTo: .footnote))
                .foregroundStyle(Color.ckTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var priceCopy: String {
        manager.annual.map { "\($0.displayPrice)/year" } ?? "—"
    }

    // MARK: - CTAs

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
                        .tint(Color.ckInk)
                } else {
                    Text(ctaText)
                        .font(CatchlightFont.ui(.medium, size: 17, relativeTo: .body))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Color.ckInk)
            .background(Color.ckEmber)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(manager.isWorking || manager.annual == nil)
        .accessibilityIdentifier("paywall-subscribe")
    }

    private var ctaText: String {
        if manager.isEligibleForIntroOffer, let trial = manager.trialDurationCopy {
            return "Start \(trial) free trial"
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

    private var legalBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your subscription auto-renews each year unless cancelled at least 24 hours before the period ends. Manage or cancel anytime in your App Store account. Catchlight is end-to-end encrypted — your Takes are never readable by us.")
                .font(CatchlightFont.ui(.regular, size: 12, relativeTo: .footnote))
                .foregroundStyle(Color.ckTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                Link("Privacy Policy",
                     destination: URL(string: "https://catchlight.app/privacy")!)
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
