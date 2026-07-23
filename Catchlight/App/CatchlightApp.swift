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
        let backgroundSync = BackgroundSyncCoordinator(
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
            // changes, reconcile notifications AND refresh the timeline
            // snapshot (2026-07-01: previously reload-only, so a Take deleted
            // on another device kept its pending alarm here and fired a banner
            // with the deleted Take's decrypted title).
            onRemoteChanges: { report in
                app.dailiesVM.applyRemoteChanges(report)
            }
        )
        self.backgroundSync = backgroundSync
        // Manual "Sync Now" hook (owner 2026-06-21) — reuses the same coordinator
        // (and so the same conflict / remote-change callbacks) as automatic passes.
        app.performManualSync = { backgroundSync.syncNow(trigger: .manualButton) }
        // Sync-on-save hook (owner 2026-07-02) — debounced + SyncMode-gated in the coordinator.
        app.syncAfterSave = { backgroundSync.syncAfterSave() }
        // Must register before the app finishes launching.
        backgroundSync.registerLaunchHandler()
        // Present reminders in the foreground too (owner-reported 2026-06-18: a
        // reminder firing while the app was open showed nothing, then went overdue).
        // The delegate is weakly held by UNUserNotificationCenter, so this installs
        // a process-lifetime singleton — set early, before any delivery.
        NotificationPresenter.install()
        // Hide scroll indicators app-wide (owner 2026-06-21). SwiftUI ScrollView and
        // List are both UIScrollView-backed, so the appearance proxy is the single
        // point that covers every current AND future scroll surface — no per-view
        // `.scrollIndicators(.hidden)` hunt, and nothing regresses when a screen is
        // added. The few explicit `.scrollIndicators(.hidden)` already in the tree
        // stay (harmless, and they document intent at those sites).
        UIScrollView.appearance().showsVerticalScrollIndicator = false
        UIScrollView.appearance().showsHorizontalScrollIndicator = false
        // UI tests: kill UIKit animations so XCUITest doesn't race the keyboard slide,
        // the UIKit pan/scroll coordination, or view transitions — a known flake source.
        // SwiftUI animations (the Focus-ring fan) are handled separately by forcing
        // reduce-motion in `body`. No effect on shipping builds.
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            UIView.setAnimationsEnabled(false)
        }
        // Detect an unexpected termination of the PREVIOUS run and stamp this launch. Must run
        // before anything can crash us, and reads/sets the flag `markCleanExit` clears on an
        // orderly background (owner 2026-07-16, D-085 extension). Content-free: build + OS +
        // device only — never anything about the user's Takes.
        DiagnosticsLog.shared.recordLaunch(build: Self.buildStamp,
                                           systemVersion: UIDevice.current.systemVersion,
                                           deviceModel: Self.deviceModel)
    }

    /// App version + the git SHA already stamped into `CFBundleVersion` by the build phase —
    /// so an exported log names the EXACT build that died.
    private static var buildStamp: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    /// Hardware identifier (e.g. "iPhone17,1") — `UIDevice.model` only ever says "iPhone".
    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: $0.pointee)) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
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
        // timeline. The UIKit timeline consumes `ui.spotlightTargetTakeID`
        // (scroll + ember pulse, then it clears the state); the pinned Obie is
        // handled by DailiesView directly. We deliberately do not open the
        // editor here — editing is gated for lapsed users, and a Spotlight tap
        // shouldn't surface the paywall.
        app.ui.exitToResting()
        // Verify the Take still exists; fail silently if not. Only checkable
        // while UNLOCKED — a cold Spotlight tap lands on the LOCKED app, where
        // the store is still the empty placeholder (D-042). Set the target
        // anyway in that case: the timeline's reveal stays pending until the
        // row appears after unlock, and never fires for a Take that's gone
        // (Spotlight may surface a deleted item before its deindex propagates).
        if app.lockState == .unlocked {
            let allTakes = (try? app.dailiesVM.store.allTakes()) ?? []
            guard allTakes.contains(where: { $0.id == uuid }) else { return }
        }
        app.ui.spotlightTargetTakeID = uuid
    }

    /// Drain a capture request queued by a widget / the New Take intent / the
    /// Control / a Shortcut (2026-06-23). Every "open Catchlight and capture"
    /// surface funnels through `CaptureRouting`'s App-Group hand-off and lands here.
    ///
    /// LOCK (D-042 / zero-Face-ID, owner 2026-06-23): if the app is UNLOCKED the
    /// capture opens the normal inline editor. If LOCKED, it lands in a blank
    /// in-memory editor IMMEDIATELY (`app.lockedCapture`) — no app-lock prompt
    /// before typing — and the single Face ID is deferred to save
    /// (`AppModel.saveLockedCapture`). The timeline/existing Takes stay gated: the
    /// store is still the empty placeholder, so nothing decrypted is on screen.
    @MainActor
    private func drainPendingCapture() {
        guard let pending = CaptureRouting.pending() else { return }
        guard let draft = makeCaptureDraft(pending) else {
            CaptureRouting.clearPending()   // .audio reserved — no-op until it ships
            return
        }
        CaptureRouting.clearPending()
        if app.lockState == .unlocked {
            // Owner 2026-06-23: a lapsed user hits the paywall instead of capturing,
            // consistent with the dock + and RootView.newTake ("open app, then paywall").
            guard app.ensureEntitled() else { return }
            app.ui.exitToResting()
            app.ui.pendingInlineNewTake = draft
        } else {
            // Zero-Face-ID capture: type now, unlock at save. Entitlement is checked
            // post-unlock in saveLockedCapture (ensureEntitled needs the unlocked state).
            // Never clobber an IN-PROGRESS locked draft (2026-07-01): a second
            // widget/Control tap while the user is mid-typing would replace their
            // text with a fresh blank. Keep the live draft; the new request was
            // cleared above, so it's a deliberate drop, not a deferred re-fire.
            guard app.lockedCapture == nil else { return }
            app.lockedCapture = draft
        }
    }

    /// Build the in-memory draft for a capture, shared by the unlocked (inline) and
    /// locked (zero-Face-ID) paths so they can't drift. nil for `.audio` (reserved
    /// until the recording engine ships). An Obie draft is pre-flagged; the store's
    /// single-Obie upsert demotes the previous Obie when it saves.
    @MainActor
    private func makeCaptureDraft(_ pending: CaptureRouting.Pending) -> Take? {
        guard pending.mode != .audio else { return nil }
        var take = app.dailiesVM.createTake()
        if pending.mode == .obie { take.isObie = true }
        if let text = pending.text, !text.isEmpty {
            take.blocks = [.textLine(text)]
        }
        // A fresh Take has no blocks; the inline editor needs a focusable block for the
        // caret/keyboard (mirrors the timeline's beginNewInlineEdit).
        if take.blocks.isEmpty { take.blocks = [.textLine("")] }
        take.normaliseActivityFloor()
        return take
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
            // Capture deep link (2026-06-23) — launcher widgets open the app via
            // `catchlight://new?mode=…` (widgetURL). Queue the request and drain;
            // if still locked, the lockState hook drains it post-unlock.
            .onOpenURL { url in
                guard let mode = CaptureRouting.mode(from: url) else { return }
                CaptureRouting.setPending(.init(mode: mode))
                drainPendingCapture()
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
                // Mark an ORDERLY exit: if this flag is still set at the next launch, the run died
                // (crash / watchdog / jetsam) and `recordLaunch` logs it. The diagnostics log is
                // in-process, so it can never witness its own death — only its absence afterwards
                // (owner 2026-07-16, D-085 extension).
                DiagnosticsLog.shared.markCleanExit()
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
                // Notice a REVOKED notification permission (owner 2026-07-16). Revoking in iOS
                // Settings silently kills every time-reminder, and nothing else in the app would
                // ever tell us. Foreground is the only moment we can see it; it writes only on a
                // CHANGE, so this can't flood despite .active firing often.
                Task { await ReminderScheduler.recordAuthorizationStatusIfChanged() }
                // Refresh which reminders are currently snoozed (owner 2026-06-21) so
                // the timeline shows "SNOOZED" not "OVERDUE". Reads the OS pending queue
                // (no key needed), so it's fine here regardless of lock state.
                app.dailiesVM.refreshSnoozedReminders()
                Task { @MainActor in
                    await subscriptionRef.refreshEntitlements()
                }
                // Task 6.13 — surface a stale/unresolvable cloud-folder
                // bookmark through the existing sync-error strip. Cheap to
                // run on every activation; no-op when sync is not configured.
                if let bookmarkError = Wiring.checkCloudBookmarkHealth() {
                    app.reportBookmarkError(bookmarkError)
                }
                // An intent/Control/Shortcut foregrounds the app via this path;
                // drain any queued capture (no-op if still locked — see below).
                drainPendingCapture()
            }
        }
        .onChange(of: app.lockState) { _, newState in
            // The app-entry unlock owns the ONLY Face ID prompt; sync never authenticates
            // (see Wiring.makeSyncEngine). On a cold launch the `.active` sync trigger above
            // races ahead of the unlock and now skips (keys aren't cached yet), so kick a
            // sync the moment the unlock caches them — inbound changes still arrive on
            // launch, with no second Face ID prompt (owner 2026-06-20).
            if newState == .unlocked {
                backgroundSync.syncNow(trigger: .appBecameActive)
                // Apply any "Dismiss" taps made while locked (owner 2026-06-22) BEFORE the
                // rebuild below — turning the reminder's alarm off in the store, so the
                // re-arm doesn't resurrect a reminder the user just dismissed.
                app.dailiesVM.applyPendingReminderActions()
                // Top up the rolling windows of any repeating reminders now the store is
                // readable (keys cached) — they don't auto-extend, so opening the app is
                // when we re-arm the next batch (owner 2026-06-21).
                app.dailiesVM.refreshRecurringSchedules()
                // A capture queued by a widget/intent before unlock now drains into
                // the blank (or pre-filled) editor (2026-06-23).
                drainPendingCapture()
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

