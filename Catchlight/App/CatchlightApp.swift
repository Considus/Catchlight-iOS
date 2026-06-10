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
//  environment and `RootView` renders onboarding or the Dailies/Search/Sequence app.
//

import SwiftUI
import CoreSpotlight
import CatchlightCore

@main
struct CatchlightApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = SessionController()

    /// User-chosen appearance preference (Settings → Appearance → Mode). Drives the
    /// top-level `preferredColorScheme` override so the whole tree follows the user's
    /// choice immediately when the segmented control changes.
    @AppStorage(SettingsViewModel.appearanceDefaultsKey) private var appearanceModeRaw: String = SettingsViewModel.AppearanceMode.system.rawValue

    /// The Phase 6 application-scope model (UI state + feature view models),
    /// composed in the single composition root.
    @State private var app: AppModel

    private let backgroundSync: BackgroundSyncCoordinator

    init() {
        let app = Wiring.makeAppModel()
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

        // Switch to the timeline and signal the target row. DailiesView reads
        // `ui.spotlightTargetTakeID` to scroll-and-flash. We deliberately do
        // not open the editor here — editing is gated for lapsed users, and a
        // Spotlight tap shouldn't surface the paywall.
        app.ui.tab = .dailies
        // Verify the Take still exists; fail silently if not.
        let allTakes = (try? app.dailiesVM.store.allTakes()) ?? []
        guard allTakes.contains(where: { $0.id == uuid }) else { return }
        app.ui.spotlightTargetTakeID = uuid
    }

    var body: some Scene {
        WindowGroup {
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

                if session.isObscured {
                    PrivacyOverlay()   // branded blur before the app-switcher snapshot
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .preferredColorScheme(
                (SettingsViewModel.AppearanceMode(rawValue: appearanceModeRaw) ?? .system).colorScheme
            )
            .task {
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
        }
        .onChange(of: scenePhase) { _, newPhase in
            session.handleScenePhase(newPhase)
            if newPhase == .background {
                backgroundSync.scheduleNext()
            }
            if newPhase == .active {
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

/// Branded blur shown over content when the app is inactive/backgrounded so the
/// system snapshot never captures decrypted Take content (Encryption Architecture §12.2).
struct PrivacyOverlay: View {
    var body: some View {
        ZStack {
            Color(red: 0x0F/255, green: 0x0E/255, blue: 0x0C/255)   // Ink
                .ignoresSafeArea()
            Text("catchlight")
                .font(.system(size: 28, weight: .light, design: .serif))   // Cormorant in prod
                .italic()
                .foregroundColor(Color(red: 0xF5/255, green: 0xED/255, blue: 0xD8/255))   // Catchlight
        }
    }
}

