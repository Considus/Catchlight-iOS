//
//  RootView.swift
//  Catchlight (iOS app target) — Phase 6 UI
//
//  The top-level composition for the product UI. Decides onboarding vs. the main
//  app, hosts the ONE surface (the timeline — the dock morphs instead of tabs
//  switching, redesign 2026-06-10), the persistent bottom dock, and the modal
//  overlays (petal fan, Take editor). All view models arrive via the environment
//  from Wiring; this view owns no domain logic.
//
//  Spine ↔ dock alignment: the timeline spine and the dock's Add button share the
//  same x. Both derive it from `CatchlightLayout.spineX(containerWidth:)` — the
//  dock's four-equal-columns formula — DailiesView for the spine and row layout,
//  BottomDockView implicitly via its own column layout (and explicitly via
//  `addButtonCentreX`). 2026-06-10 fix: the earlier fixed `spineLeading = 32`
//  never matched the dock's real Add centre (~58pt on a 393pt screen).
//

import SwiftUI
import CatchlightCore

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui
    @Environment(FirstRunOrientationState.self) private var orientation
    @Environment(\.scenePhase) private var scenePhase

    /// Branded splash shown on every cold launch (owner 2026-06-14). `.task` runs
    /// once per RootView lifetime, so warm resumes from the background don't
    /// re-show it.
    @State private var showSplash = true

    var body: some View {
        // ZStack with a full-bleed background guarantees children receive a full-screen
        // size proposal. A bare Group inherits the parent's bounded proposal, which left
        // OnboardingView's StepScaffold with a partial-height frame (half-screen
        // background, mid-screen floating button, clipped ScrollView).
        ZStack {
            Color.ckBackground.ignoresSafeArea()
            if app.needsOnboarding {
                if let onboardingVM = app.onboardingVM {
                    OnboardingView()
                        .environment(onboardingVM)
                        .transition(.opacity)
                }
            } else if app.lockState != .unlocked {
                // D-042: an onboarded-but-locked user sees the branded LockView
                // INSTEAD of the timeline — so `mainApp`'s side effects (paywall
                // .task, sync) don't run against the locked placeholder store, and
                // the (empty) timeline is never visible or interactive.
                LockView()
                    .transition(.opacity)
            } else {
                mainApp
                    .transition(.opacity)
            }

            if showSplash {
                // The splash shares the Welcome screen's exact layout (brand mark
                // + content slots), so dismissing it crossfades to onboarding's
                // Welcome with the brand mark appearing static — only the text
                // swaps (owner 2026-06-14). On the onboarded path it simply
                // crossfades to the timeline.
                WelcomeContent(mode: .splash)
                    .transition(.opacity)
                    .zIndex(100)   // above content + overlays while it holds
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.4), value: app.needsOnboarding)
        .animation(.easeInOut(duration: 0.4), value: app.lockState)
        .task {
            // Hold the launch-screen branding long enough to actually READ the
            // tagline (owner 2026-06-16: 1.2s was too fast). ~2.5s solo.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            // Keep the splash as the BACKDROP through the unlock so the happy path
            // never flashes the lock screen (owner 2026-06-16): splash → Face ID over
            // it → crossfade straight to the timeline on success. The lock screen is
            // revealed only if the user cancels (lockState becomes `.failed` behind
            // the splash, so the crossfade lands on LockView's "Try Again").
            if app.lockState == .locked { await app.attemptUnlock() }
            withAnimation(.easeInOut(duration: 0.5)) { showSplash = false }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Start the time-away clock for the grace re-lock (option 1).
                app.noteEnteredBackground()
            case .active:
                // Warm resume only — the splash `.task` handles cold launch. Re-lock
                // if we were away past the grace window (or the device-lock notice
                // already re-locked us), then auto-present the unlock now that we're
                // foreground (never prompt while backgrounded).
                guard !showSplash else { return }
                Task {
                    app.relockIfAwayTooLong()
                    if app.lockState == .locked { await app.attemptUnlock() }
                }
            default:
                break
            }
        }
    }

    private var mainApp: some View {
        @Bindable var ui = ui
        // The body is assembled from small computed properties (`timeline`,
        // `dock`) rather than a single large ZStack ViewBuilder — an inline
        // conditional + modifier chain produced a phantom "cannot convert Color
        // to Bool" diagnostic from SwiftUI's type-checker.
        return ZStack(alignment: .bottom) {
            Color.ckBackground.ignoresSafeArea()

            timeline   // full opacity behind the fan — the veil does the work

            dock
        }
        .overlay { editorOverlay }
        .overlay { petalFanOverlay }
        .overlay { obieIntroOverlay }
        .sheet(isPresented: $ui.isSettingsPresented) {
            SettingsView()
        }
        .sheet(isPresented: $ui.isConflictSheetPresented) {
            ConflictResolutionView()
                .environment(app.dailiesVM)
        }
        .sheet(isPresented: $ui.isPaywallPresented) {
            PaywallView()
                .environment(app)
        }
        .onChange(of: app.needsOnboarding) { _, isOnboarding in
            // Post-onboarding paywall trigger (Task 6.20). When the flag flips
            // false we've just exited onboarding; surface the paywall if the
            // user isn't entitled. Wrapped in a brief delay so the onboarding
            // dismiss animation finishes first.
            guard !isOnboarding else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                app.presentPaywallIfNeededAfterOnboarding()
            }
        }
        .task {
            // Lapsed COLD-LAUNCH paywall (2026-06-10): the onChange above only
            // fires on the onboarding → main transition; an already-onboarded
            // user launching while lapsed never saw the auto-present (only the
            // banner). Idempotent — no-ops when entitled or still onboarding;
            // launch-time `.unknown` is permissive so real users aren't flashed
            // a paywall before entitlements resolve. Same 400 ms grace as the
            // onChange path so the sheet never races an appearance transition.
            try? await Task.sleep(nanoseconds: 400_000_000)
            app.presentPaywallIfNeededAfterOnboarding()
        }
        .alert("Replace your Obie?",
               isPresented: Binding(
                get: { app.dailiesVM.pendingObieConflict != nil },
                set: { if !$0 { app.dailiesVM.cancelObieReplacement() } }
               )) {
            Button("Replace", role: .destructive) {
                app.dailiesVM.confirmObieReplacement()
                orientation.didDismissObieIntro()
            }
            Button("Keep current", role: .cancel) {
                app.dailiesVM.cancelObieReplacement()
                orientation.didDismissObieIntro()
            }
        } message: {
            Text("Only one Take can be your Obie. This will replace the current one.")
        }
    }

    // MARK: - Surface & chrome
    //
    // These are split into separate computed properties (rather than inlined in the
    // `mainApp` ZStack) so each ViewBuilder stays simple enough for SwiftUI's
    // type-checker.

    /// Opacity for the DOCK behind the petal fan. The timeline itself stays at
    /// full opacity — the fan's ckDim veil (background @90%) provides the
    /// recede on its own (owner decision 2026-06-11; HiFi §4 technique).
    private var fanOpacity: Double { ui.isPetalFanPresented ? 0.18 : 1 }

    /// The ONE surface — the timeline. The dock's filtering/searching states
    /// narrow it live via `ui.activeTimelineFilter` (read inside DailiesView).
    private var timeline: some View {
        DailiesView().environment(app.dailiesVM)
    }

    /// The persistent bottom dock (morphs between resting / filtering / searching).
    private var dock: some View {
        BottomDockView(onNewTake: { newTake() })
            .environment(ui)
            .opacity(fanOpacity)
    }

    // MARK: - Overlays

    @ViewBuilder
    private var editorOverlay: some View {
        if let take = ui.editorTake {
            TakeEditView(take: take)
                .environment(app.dailiesVM)
                .environment(ui)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var petalFanOverlay: some View {
        if let take = ui.petalFanTake {
            GeometryReader { geo in
                PetalFanView(
                    take: take,
                    hubCentre: ui.petalFanOrigin == .zero
                        ? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                        : ui.petalFanOrigin,
                    onCommit: { isNote, isTask, hasReminder, isObie in
                        // Task 6.20: petal-fan commit is a mutation — gate it.
                        guard app.ensureEntitled() else {
                            ui.closePetalFan()
                            return
                        }
                        if ui.editorTake?.id == take.id {
                            // The editor is open for this Take: hand the selection
                            // to it so the Task Mark reshapes the LIVE blocks the
                            // user is editing (and reminder/Obie ride the editor's
                            // own save on dismiss). Routing through the store here
                            // would operate on the pre-typing copy.
                            ui.editorFanCommand = UIState.EditorFanCommand(
                                token: UUID(),
                                isNote: isNote, isTask: isTask,
                                hasReminder: hasReminder, isObie: isObie
                            )
                        } else {
                            app.dailiesVM.applyActivityTypes(
                                to: take,
                                isNote: isNote, isTask: isTask,
                                hasReminder: hasReminder, isObie: isObie
                            )
                        }
                        ui.closePetalFan()
                    },
                    onDismiss: { ui.closePetalFan() }
                )
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    /// Hint 4 — the Obie introduction. A floating tooltip that sits lightly on top
    /// of the live UI (no dim overlay). Tapping anywhere dismisses; the dailies VM's
    /// own confirm/cancel alert ALSO dismisses (wired via the alert's button actions).
    @ViewBuilder
    private var obieIntroOverlay: some View {
        if orientation.showObieIntro {
            ZStack(alignment: .top) {
                // Transparent catcher so a tap anywhere off the bubble counts as
                // "tapping elsewhere" and dismisses the hint.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { orientation.didDismissObieIntro() }

                OrientationTooltip(
                    text: "This is your Obie — your one most important Take. It stays at the top of everything until it's done. Long press the Iris to instantly make any Take an Obie.",
                    arrowEdge: .top,
                    maxWidth: 300
                )
                .padding(.top, 80)
                .padding(.horizontal, 24)
                .onTapGesture { orientation.didDismissObieIntro() }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: orientation.showObieIntro)
        }
    }

    // MARK: - New item actions

    /// Invoked directly by the dock's Add button (RESTING and FILTERING states —
    /// redesign 2026-06-10, no bloom). Creates a blank Take and opens the editor.
    private func newTake() {
        // Task 6.20: lapsed users hit the paywall instead of creating a Take.
        guard app.ensureEntitled() else { return }
        let take = app.dailiesVM.createTake()
        ui.openEditor(for: take)
    }
}

#Preview("Root — main (Night)") {
    let store = InMemoryTakeStore()
    for t in SeedTakes.make() { try? store.upsert(t) }
    let app = AppModel.preview(store: store, onboarded: true)
    return RootView()
        .environment(app)
        .environment(app.ui)
        .environment(app.orientation)
        .environment(app.conflictQueue)
        .preferredColorScheme(.dark)
}

#Preview("Root — onboarding") {
    let app = AppModel.preview(store: InMemoryTakeStore(), onboarded: false)
    return RootView()
        .environment(app)
        .environment(app.ui)
        .environment(app.orientation)
        .environment(app.conflictQueue)
        .preferredColorScheme(.dark)
}
