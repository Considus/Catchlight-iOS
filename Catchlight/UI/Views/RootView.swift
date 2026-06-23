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
    ///
    /// SUPPRESSED under `--uitesting`: the splash sits at `zIndex 100` over the
    /// timeline for ~2.5s, so an XCUITest that taps `add-button` at launch hits an
    /// OCCLUDED element ("Failed to scroll to visible … kAXErrorCannotComplete")
    /// before the curtain lifts — it mass-failed CoreFlows/BlockEditor/TwoTap on
    /// CI. Tests don't need the branding flourish, and skipping it also reclaims
    /// ~2.5s per launch across the suite. Same flag `Wiring.makeAppModel` reads.
    @State private var showSplash = !ProcessInfo.processInfo.arguments.contains("--uitesting")

    /// Cold-launch splash hold, tuned INDEPENDENTLY for the two destinations (owner
    /// 2026-06-18). The destination is known when the splash `.task` runs, keyed on
    /// `app.needsOnboarding`:
    ///  • onboarding — a first impression; hold long enough to read the tagline.
    ///  • onboarded app — a returning user; get them to the timeline sooner.
    /// Two knobs, easy to retune on device.
    private static let splashHoldOnboarding: TimeInterval = 2.5
    private static let splashHoldOnboarded: TimeInterval = 1.0

    /// Suppress the auto-presented Face ID while a capture is pending — zero-Face-ID
    /// capture lands in the locked editor instead (owner 2026-06-23). Covers the
    /// window BEFORE `drainPendingCapture` consumes the App-Group hand-off
    /// (`CaptureRouting.pending()`) AND after, when `app.lockedCapture` is set.
    private var capturePending: Bool {
        app.lockedCapture != nil || CaptureRouting.pending() != nil
    }

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
                if let seed = app.lockedCapture {
                    // Zero-Face-ID capture (owner 2026-06-23): a widget/intent that
                    // arrived while locked lands HERE — the blank editor only, no
                    // timeline. The store is still the empty placeholder, so no
                    // decrypted content is on screen; the single Face ID is deferred
                    // to save. `.id` so a fresh capture replaces the editor cleanly.
                    LockedCaptureView()
                        .id(seed.id)
                        .transition(.opacity)
                } else if capturePending {
                    // A capture is incoming but not yet built (the App-Group hand-off
                    // is set; drainPendingCapture hasn't run). Hold the brand
                    // background — same as LockedCaptureView's — instead of flashing
                    // LockView for a sub-second before the editor appears (owner
                    // 2026-06-23). The editor's content then simply appears on it.
                    Color.ckBackground.ignoresSafeArea()
                } else {
                    // D-042: an onboarded-but-locked user sees the branded LockView
                    // INSTEAD of the timeline — so `mainApp`'s side effects (paywall
                    // .task, sync) don't run against the locked placeholder store, and
                    // the (empty) timeline is never visible or interactive.
                    LockView()
                        .transition(.opacity)
                }
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
            // Splash suppressed (UI testing): still drive the unlock if we somehow
            // launched locked, but skip the 2.5s branding hold entirely.
            guard showSplash else {
                if app.lockState == .locked && !capturePending { await app.attemptUnlock() }
                return
            }
            // Hold the launch-screen branding, independently per destination (owner
            // 2026-06-18): longer into onboarding (read the tagline), shorter into the
            // onboarded app (returning user). `needsOnboarding` is settled by now.
            let hold = app.needsOnboarding ? Self.splashHoldOnboarding : Self.splashHoldOnboarded
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            // Keep the splash as the BACKDROP through the unlock so the happy path
            // never flashes the lock screen (owner 2026-06-16): splash → Face ID over
            // it → crossfade straight to the timeline on success. The lock screen is
            // revealed only if the user cancels (lockState becomes `.failed` behind
            // the splash, so the crossfade lands on LockView's "Try Again").
            if app.lockState == .locked && !capturePending { await app.attemptUnlock() }
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
                    if app.lockState == .locked && !capturePending { await app.attemptUnlock() }
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

            // The search field rides the keyboard as a UIKit inputAccessoryView
            // (2026-06-20) — OS-positioned, so it sits correctly on device with no
            // manual frame math. Zero-size here; it only owns the keyboard accessory.
            // Active while searching with the keyboard raised.
            KeyboardSearchBar(
                query: $ui.searchQuery,
                isActive: ui.dockMode == .searching && ui.searchKeyboardUp,
                onCancel: { ui.exitToResting() },
                onSubmitDismiss: { ui.lowerSearchKeyboard() }
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        // Opt the whole surface OUT of SwiftUI's automatic keyboard avoidance. Nothing
        // needs it: the search bar rides the keyboard as a UIKit inputAccessoryView
        // (OS-positioned) and the edit-in-place editor pins its caret by driving the
        // timeline scroll offset directly (D-048). Without this, native avoidance flung
        // the bottom-aligned resting dock up to the heading whenever it happened to be
        // showing while a keyboard was up — the stray-toolbar bug (owner 2026-06-20).
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
        .fullScreenCover(isPresented: $ui.isStoryboardPresented) {
            StoryboardView(onClose: { ui.isStoryboardPresented = false })
                .environment(app.dailiesVM)
                .environment(ui)
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
        .alert("Make this your Obie?",
               isPresented: Binding(
                get: { app.dailiesVM.pendingObieConflict != nil },
                set: { if !$0 { app.dailiesVM.cancelObieReplacement() } }
               )) {
            Button("Make Obie") {
                app.dailiesVM.confirmObieReplacement()
                orientation.didDismissObieIntro()
            }
            Button("Cancel", role: .cancel) {
                app.dailiesVM.cancelObieReplacement()
                orientation.didDismissObieIntro()
            }
        } message: {
            // Owner copy 2026-06-17: frame it as the existing Obie returning to the
            // timeline (not "replaced"), since nothing is lost — only one Take can be
            // the Obie at a time.
            Text("Your existing Obie returns to the timeline — only one Take can be your Obie.")
        }
    }

    // MARK: - Surface & chrome
    //
    // These are split into separate computed properties (rather than inlined in the
    // `mainApp` ZStack) so each ViewBuilder stays simple enough for SwiftUI's
    // type-checker.

    /// Opacity for the DOCK while a focus surface is up. Behind the petal fan the
    /// fan's own ckDim veil does the timeline recede; while editing in place the
    /// timeline masks itself (DailiesView), and the dock recedes + goes inert here so
    /// it can't start a competing action mid-edit (owner 2026-06-17).
    /// True while the search keyboard (and its docked search bar) is up. The bottom
    /// dock is redundant then — the search bar IS the UI — so hide + inert it, exactly
    /// as for editing. Leaving it live let its swipe-up-for-Settings gesture compete
    /// with the timeline scroll (owner 2026-06-20: scrolling opened Settings instead).
    private var searchKeyboardUp: Bool {
        ui.dockMode == .searching && ui.searchKeyboardUp
    }

    private var fanOpacity: Double {
        // Editing / search hide the dock OUTRIGHT — and this is checked BEFORE the fan
        // dim (owner 2026-06-21): a Focus ring opened FROM the editor sets BOTH
        // `isEditingInPlace` and `isPetalFanPresented`, and if the fan check won the dock
        // re-appeared at 18% and the keyboard's safe-area avoidance shoved it mid-screen
        // — the "ghostly toolbar" bug. While editing, the keyboard toolbar replaces the
        // dock, so hide it outright regardless of the fan. (The original reason still
        // holds: even at low opacity the keyboard pushes a stray dock over the heading.)
        if ui.isEditingInPlace || searchKeyboardUp { return 0 }
        // The 0.18 dim is for a fan opened from the RESTING timeline (dock recedes
        // behind the veil but stays visible).
        if ui.isPetalFanPresented { return 0.18 }
        return 1
    }

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
            // Inert while editing in place (so a stray tap can't open a second editor)
            // AND while the search keyboard is up (so its swipe-up Settings gesture
            // doesn't hijack the timeline scroll — owner 2026-06-20).
            .allowsHitTesting(!ui.isEditingInPlace && !searchKeyboardUp)
    }

    // MARK: - Overlays

    @ViewBuilder
    private var petalFanOverlay: some View {
        if let take = ui.petalFanTake {
            GeometryReader { geo in
                PetalFanView(
                    take: take,
                    hubCentre: ui.petalFanOrigin == .zero
                        ? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                        : ui.petalFanOrigin,
                    containerWidth: geo.size.width,
                    // Lift the tapped Take lit above the veil only when the fan
                    // blooms from a timeline Iris (real origin). From the editor
                    // footer the origin is .zero (screen centre) and the editor is
                    // already the context, so no spotlight card there.
                    showsFocusCard: ui.petalFanOrigin != .zero,
                    onCommit: { isNote, isTask, hasReminder, reminderDate, reminderAlarm, reminderAllDay, reminderRecurrence, isObie in
                        // Task 6.20: petal-fan commit is a mutation — gate it.
                        guard app.ensureEntitled() else {
                            ui.closePetalFan()
                            return
                        }
                        if ui.editingTakeID == take.id {
                            // Edit-in-place: the Take is being edited inline. Hand the
                            // selection to that editor's draft so it rides the inline
                            // save — routing to the store here lets the stale draft
                            // revert it on save (e.g. an Obie change).
                            ui.inlineFanCommand = UIState.EditorFanCommand(
                                token: UUID(),
                                isNote: isNote, isTask: isTask,
                                hasReminder: hasReminder, reminderDate: reminderDate,
                                reminderAlarm: reminderAlarm, reminderAllDay: reminderAllDay,
                                reminderRecurrence: reminderRecurrence,
                                isObie: isObie
                            )
                        } else {
                            app.dailiesVM.applyActivityTypes(
                                to: take,
                                isNote: isNote, isTask: isTask,
                                hasReminder: hasReminder, reminderDate: reminderDate,
                                reminderAlarm: reminderAlarm, reminderAllDay: reminderAllDay,
                                reminderRecurrence: reminderRecurrence,
                                isObie: isObie
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
        // Edit-in-place Phase 2 (2026-06-17): the new Take is created and edited IN
        // PLACE on the timeline (at the Order-appropriate end), not in the
        // top-anchored overlay. DailiesView picks this up and focuses it.
        ui.pendingInlineNewTake = app.dailiesVM.createTake()
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
