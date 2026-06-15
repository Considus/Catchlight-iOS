//
//  CatchlightApp.swift
//  Catchlight (iOS app target)
//
//  Application entry point. Wires the architecture-level concerns:
//    • background-sync task registration (brief §7.8)
//    • scene-phase memory security + privacy overlay (brief §5.9, §12)
//    • jailbreak warning surface (brief §5.11)
//
//  Phase 6 adds the product UI: the AppModel (built by Wiring) is injected into the
//  environment and `RootView` renders onboarding or the one-surface timeline app
//  (dock redesign 2026-06-10 — the dock morphs; there are no separate screens).
//

import SwiftUI
import UIKit
import CoreSpotlight
import CatchlightCore

@main
struct CatchlightApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: SessionController

    /// User-chosen appearance preference (Settings → Appearance → Mode). Drives the
    /// top-level `preferredColorScheme` override so the whole tree follows the user's
    /// choice immediately when the segmented control changes.
    @AppStorage(SettingsViewModel.appearanceDefaultsKey) private var appearanceModeRaw: String = SettingsViewModel.AppearanceMode.system.rawValue

    /// The Phase 6 application-scope model (UI state + feature view models),
    /// composed in the single composition root.
    @State private var app: AppModel

    private let backgroundSync: BackgroundSyncCoordinator

    init() {
        // Create the crypto session first so it can be shared: AppModel drives
        // unlock through it imperatively, while this view observes its `isObscured`
        // for the privacy overlay (hence the @StateObject wrapper over the SAME
        // instance).
        let session = SessionController()
        let app = Wiring.makeAppModel(session: session)
        self._session = StateObject(wrappedValue: session)
        self._app = State(initialValue: app)
        // Background sync runs off the main thread; surfaced conflicts hop back to
        // the main actor and land in `AppModel.conflictQueue` for the UI to resolve.
        self.backgroundSync = BackgroundSyncCoordinator(
            makeEngine: { Wiring.makeSyncEngine() },
            onConflicts: { conflicts in
                app.conflictQueue.enqueue(conflicts)
            },
            // Task 3.9 — non-blocking sync error strip.
            onSyncError: { error in
                app.reportSyncError(error)
            },
            // Task 3.9 — quarantine notice strip.
            onQuarantined: { ids in
                app.reportQuarantined(ids)
            },
            // Foreground sync (2026-06-10) — when a pass applied remote
            // changes, refresh the timeline snapshot so they show immediately.
            // (Dock redesign: the timeline is the ONE surface; its live filter
            // re-derives from the same snapshot, so this reload covers all
            // dock states.)
            onRemoteChanges: { _ in
                app.dailiesVM.reload()
            }
        )
        // Must register before the app finishes launching.
        backgroundSync.registerLaunchHandler()
    }

    /// Capture the app handle so the scenePhase observer can drive subscription
    /// refreshes off the same instance without re-reading `_app` (which would
    /// strip @MainActor isolation inside the closure).
    private var subscriptionRef: SubscriptionManager { app.subscription }

    /// Task 6.19 — extract the Take UUID from a Spotlight activity payload and
    /// route the UI to it. Handles both the CSSearchableItem default activity
    /// (UUID under `CSSearchableItemActivityIdentifier`) and the named
    /// `viewTake` activity (UUID under `takeID`). Fails silently if the Take
    /// no longer exists in the store — Spotlight may surface a deleted item
    /// before its async deindex propagates.
    @MainActor
    private func handleSpotlight(_ activity: NSUserActivity) {
        let raw = (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String)
            ?? (activity.userInfo?[SpotlightConstants.userInfoTakeIDKey] as? String)
        guard let raw, let uuid = UUID(uuidString: raw) else { return }

        // Return the dock to RESTING (clearing any live filter) BEFORE setting
        // the target, so the row is guaranteed visible on the unfiltered
        // timeline. DailiesView reads `ui.spotlightTargetTakeID` to
        // scroll-and-flash. We deliberately do not open the editor here —
        // editing is gated for lapsed users, and a Spotlight tap shouldn't
        // surface the paywall.
        app.ui.exitToResting()
        // Verify the Take still exists; fail silently if not.
        let allTakes = (try? app.dailiesVM.store.allTakes()) ?? []
        guard allTakes.contains(where: { $0.id == uuid }) else { return }
        app.ui.spotlightTargetTakeID = uuid
    }

    var body: some Scene {
        WindowGroup {
            // Root GeometryReader: the ONE place the real window safe-area
            // insets are visible (everything inside runs full-bleed via
            // `.ignoresSafeArea(.container)` below). The top inset is passed
            // down the environment for pinned chrome (DailiesView heading).
            GeometryReader { rootGeo in
            ZStack {
                Color.ckBackground.ignoresSafeArea()

                RootView()
                    .environment(app)
                    .environment(app.ui)
                    .environment(app.orientation)
                    .environment(app.conflictQueue)
                    .environmentObject(session)

                if session.jailbreakWarning {
                    JailbreakBanner()
                }

                // Cover decrypted content before the app-switcher snapshot — but
                // ONLY when unlocked. While locked, LockView is already on screen and
                // reveals nothing, so the overlay would just flash over it during the
                // unlock sheet (D-042).
                if session.isObscured && app.lockState == .unlocked {
                    PrivacyOverlay()
                }

                #if DEBUG
                // Section 2b — on-device safe-area readout (gated behind a
                // Settings DEBUG toggle, off by default). Reads the env values
                // from the modifiers below; raw insets come straight off rootGeo.
                DebugInsetReadout(rawTop: rootGeo.safeAreaInsets.top,
                                  rawBottom: rootGeo.safeAreaInsets.bottom)
                #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // `.container` ONLY (2026-06-10 dock redesign): the bare
            // `.ignoresSafeArea()` also ignored the KEYBOARD region, which
            // pinned the bottom dock underneath the software keyboard — fatal
            // once the dock hosts the search field and its ×/confirm buttons
            // (the keyboard's emoji key sat exactly over ×). Container edges
            // keep the full-bleed layout; the keyboard inset now lifts the
            // dock above the keyboard while searching.
            .ignoresSafeArea(.container)
            .environment(\.deviceTopInset, rootGeo.safeAreaInsets.top)
            // Section 4 / D-041 — mirror of deviceTopInset for the BOTTOM edge
            // (home-indicator zone). The app runs full-bleed, so this is the one
            // place the real bottom inset is visible; the dock + onboarding pill
            // row read it from the environment to rest above the home indicator.
            .environment(\.deviceBottomInset, rootGeo.safeAreaInsets.bottom)
            .preferredColorScheme(
                (SettingsViewModel.AppearanceMode(rawValue: appearanceModeRaw) ?? .system).colorScheme
            )
            .task {
                // Remove any decrypted export files a crash or an unfinished
                // share sheet left in tmp — the only other cleanup path is the
                // share sheet's own completion handler.
                ExportCoordinator.sweepStaleExports()
                // Task 6.21: kick off the subscription state machine on first
                // launch. `startObservingUpdates` is idempotent; entitlements
                // are then re-checked on every scenePhase → .active.
                subscriptionRef.startObservingUpdates()
                await subscriptionRef.loadProduct()
                await subscriptionRef.refreshEntitlements()
            }
            // Task 6.19 — Spotlight deep link. iOS routes a Spotlight tap on
            // a Catchlight result through this activity type; we pull the
            // Take UUID out of userInfo and let DailiesView focus the row.
            // `CSSearchableItemActionType` covers taps on `CSSearchableItem`s
            // directly; the named activity type catches the equivalent
            // NSUserActivity path if we ever swap mechanisms.
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                handleSpotlight(activity)
            }
            .onContinueUserActivity(SpotlightConstants.userActivityType) { activity in
                handleSpotlight(activity)
            }
            // D-042 — re-lock when the DEVICE locks (auto-lock or manual), not on
            // mere app-switching. `protectedDataWillBecomeUnavailable` fires on
            // device lock only; the app drops its keys + encrypted store and the
            // next foreground shows LockView. Re-lock cadence thus follows the
            // user's iOS Auto-Lock, not an app-defined timer.
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
                app.relock()
            }
            }   // GeometryReader (rootGeo)
        }
        .onChange(of: scenePhase) { _, newPhase in
            session.handleScenePhase(newPhase)
            if newPhase == .background {
                // Push this session's edits out before suspension (runs under
                // a background-task assertion with the in-memory keys), then
                // schedule the opportunistic BG refresh.
                backgroundSync.syncNow(trigger: .appEnteringBackground)
                backgroundSync.scheduleNext()
            }
            if newPhase == .active {
                // Foreground sync is the PRIMARY sync path on hardware: the
                // `.userPresence` master key cannot be unwrapped by a cold
                // background task, so opening the app is when changes from
                // other devices arrive. Throttled internally (60 s) because
                // `.inactive → .active` also fires for Face ID sheets,
                // Notification Centre, and the app switcher.
                backgroundSync.syncNow(trigger: .appBecameActive)
                Task { @MainActor in
                    await subscriptionRef.refreshEntitlements()
                }
                // Task 6.13 — surface a stale/unresolvable cloud-folder
                // bookmark through the existing sync-error strip. Cheap to
                // run on every activation; no-op when sync is not configured.
                if let bookmarkError = Wiring.checkCloudBookmarkHealth() {
                    app.reportBookmarkError(bookmarkError)
                }
            }
        }
    }
}

/// Non-blocking jailbreak advisory, surfaced over the UI (brief §5.11). Kept minimal
/// and dismissible-by-ignoring; the security posture is enforced elsewhere.
struct JailbreakBanner: View {
    var body: some View {
        VStack {
            Text(JailbreakDetector.warningMessage)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.top, 8)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(JailbreakDetector.warningMessage)
    }
}

/// Branded curtain shown over content when the app is inactive/backgrounded so the
/// system snapshot never captures decrypted Take content (Encryption Architecture
/// §12.2). Mirrors the splash / lock screen — the brand mark centred on the adaptive
/// Paper/Ink background — so the app-switcher card reads as Catchlight, on-brand in
/// both appearances (D-042: was a plain dark "catchlight" wordmark).
struct PrivacyOverlay: View {
    var body: some View {
        ZStack {
            Color.ckBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Image("catchlight-icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                Image("catchlight-wordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 44)
            }
            .accessibilityHidden(true)
        }
    }
}

