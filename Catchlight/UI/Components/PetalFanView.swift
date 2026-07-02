//
//  PetalFanView.swift
//  Catchlight (iOS app target) — Phase 6 UI · constellation redesign 2026-06-11
//
//  The activity-type selector — the signature Catchlight interaction, rebuilt to
//  the owner-approved constellation (HiFi v1.6 §10, "organic peel"):
//
//  LAYOUT — petals settle on an arc to the RIGHT of the timeline: angles
//  −80° / −26.7° / +26.7° / +80° from horizontal (screen frame, y down), all at
//  R = 68pt from the Iris centre; order Notes · Tasks · Reminders · Obie
//  top→bottom. Petals (Marks) are 44pt — they FILL their 44pt touch circles, to
//  match the dock buttons + timeline Iris (owner 2026-06-15; the hub Iris and R
//  were scaled 36→44 / 56→68 in step so the Focus ring keeps its spacing:
//  adjacent chord 61 > 44; Iris clearance 68 > 44). Petals deliberately pass ABOVE
//  the Take card. On the Obie row the fan covers the page heading — approved.
//
//  MOTION — one fluid action in two distinct movements:
//    1 "emergence": the stacked deck (Notes on top, the others invisibly
//      beneath) rises STRAIGHT UP out of the Iris to R at −90°, easeInOutCubic,
//      340ms. The Iris does not rotate yet — the buttons "live" in the Iris.
//    2 "spread": the Iris rotation (90° CW, 700ms, overshooting ~6° then
//      settling) begins at the first peel, and Obie/Reminders/Tasks peel off
//      the deck DURING the rise (peels at 120/185/250ms), each spiralling
//      outward along its own arc (radius blends to R over 520ms) while
//      sweeping clockwise at ~5.5ms/° with easeOutBack (s 1.15) landings —
//      cascading arrivals, soft ~6–8° overshoot. Notes alone rides the deck
//      to the top, then nudges its final 10°.
//  CLOSE — the TRUE time-mirror of the open played 1.25× faster (exits are
//  quicker than entrances): petals kick slightly outward (the reversed
//  overshoot), spiral back into the descending deck, and the Iris reverses its
//  OWN turn on the SAME mirrored clock (it nudges to ~96° then sweeps back to 0 —
//  the open's soft-catch run backwards), so hub and Marks land together rather
//  than the Iris finishing first. Reduce Motion replaces all of it with a fade.
//
//  STYLE — petals share the dock-button language: background-colour face
//  (readable above cards), 1.5pt Ember@35% ring, no shadow, Ember glyphs at
//  the light weight; the Obie petal draws the ring+specular glyph in
//  ckTextObie. Active petals reverse like the dock toggles (Ember fill +
//  background glyph). The veil is ckDim (background @90%, no blur): it recedes
//  everything beneath it, then the TAPPED Take's card is lifted back LIT above
//  the veil (owner 2026-06-16) so only that Take, its Iris (the rotating hub),
//  and the Focus-ring stay readable while the rest of the timeline + chrome dim
//  away (`showsFocusCard` / `TakeCardSurface`). From the editor footer there is
//  no spotlight card — the editor is the context there.
//
//  Petal taps toggle the working selection; tapping the veil COMMITS and
//  closes (unchanged semantics — Note remains the floor).
//

import SwiftUI
import CatchlightCore

struct PetalFanView: View {
    let take: Take
    /// Screen-space point of the hub (centre of the tapped circle).
    let hubCentre: CGPoint
    /// Full overlay width (screen width) — used to reconstruct the tapped Take's
    /// card frame so a LIT copy can be lifted above the dim veil. See `focusCard`.
    var containerWidth: CGFloat = 0
    /// Whether to lift the tapped Take's card above the veil (owner 2026-06-16).
    /// True when the fan blooms from a timeline Iris (`hubCentre` is a real row);
    /// false from the editor footer (origin = screen centre — the editor IS the
    /// context there, so no card to spotlight).
    var showsFocusCard: Bool = false
    /// `reminderDate` carries the time chosen in the picker (nil when no Reminder).
    /// `reminderAlarm` / `reminderAllDay` carry the model-C picker choices (owner
    /// 2026-06-18) — undefined/ignored when `hasReminder` is false.
    let onCommit: (_ isNote: Bool, _ isTask: Bool, _ hasReminder: Bool, _ reminderDate: Date?, _ reminderAlarm: Bool, _ reminderAllDay: Bool, _ reminderRecurrence: TimeReminder.Recurrence, _ reminderWeekdays: Set<Int>, _ reminderLocation: LocationTrigger?, _ isObie: Bool) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    /// Default "when" a freshly-added reminder opens to — now a user preference
    /// (Settings → Reminders → Default timing (hrs); owner 2026-06-18). Read at call
    /// time from UserDefaults so it always reflects the current setting; the picker
    /// opens here and the user refines or accepts it.
    static var defaultReminderDate: Date {
        SettingsViewModel.DefaultReminderHours.current.date()
    }

    // Working selection (mutated as petals are tapped).
    @State private var isNote: Bool
    @State private var isTask: Bool
    @State private var hasReminder: Bool
    @State private var isObie: Bool
    /// The working Reminder time. Seeded from the Take's existing reminder (or the
    /// +24h default) and edited by the picker that pops when the Reminder Mark is
    /// tapped on (owner 2026-06-17).
    @State private var reminderDate: Date
    /// Model-C picker choices (owner 2026-06-18): whether the "when" also rings, and
    /// whether it's a date-only (all-day) placement. Seeded from any existing reminder.
    @State private var reminderAlarm: Bool
    @State private var reminderAllDay: Bool
    /// How often the reminder repeats (owner 2026-06-21). Seeded from any existing
    /// reminder; `.none` for a one-shot.
    @State private var reminderRecurrence: TimeReminder.Recurrence
    /// The weekdays a WEEKLY reminder repeats on (owner 2026-06-23) — empty for every other
    /// cadence. Seeded from any existing reminder; edited by the picker's day strip.
    @State private var reminderWeekdays: Set<Int>
    /// The location ("where") for this reminder (owner 2026-06-23) — nil for time-only.
    @State private var reminderLocation: LocationTrigger?
    /// Drives the date/time picker sheet the Reminder Mark pops.
    @State private var showingReminderPicker = false

    private enum FanPhase: Equatable {
        case opening(start: Date)
        case open
        case closing(start: Date, commit: Bool)
        /// Terminal STATIC state, set the instant the fan commits — BEFORE the overlay
        /// is removed. `.closing` keeps the TimelineView animating, which prevented
        /// SwiftUI from tearing the view down when `petalFanTake` went nil: the veil
        /// lingered in `.closing` and ate every tap, stranding the user over a
        /// perfectly-fine editor (owner-reported lockup 2026-06-18, confirmed via an
        /// on-device state trace: `FAN:nil/closing`). `.dismissed` is non-animating
        /// (TimelineView pauses → the view can be removed) and renders fully
        /// retracted/invisible, matching the close animation's end frame so there's no
        /// flash.
        case dismissed
    }
    @State private var phase: FanPhase

    init(take: Take,
         hubCentre: CGPoint,
         containerWidth: CGFloat = 0,
         showsFocusCard: Bool = false,
         onCommit: @escaping (Bool, Bool, Bool, Date?, Bool, Bool, TimeReminder.Recurrence, Set<Int>, LocationTrigger?, Bool) -> Void,
         onDismiss: @escaping () -> Void) {
        self.take = take
        self.hubCentre = hubCentre
        self.containerWidth = containerWidth
        self.showsFocusCard = showsFocusCard
        self.onCommit = onCommit
        self.onDismiss = onDismiss
        _isNote = State(initialValue: take.isNote)
        _isTask = State(initialValue: take.isTask)
        _hasReminder = State(initialValue: take.timeReminder != nil)
        _isObie = State(initialValue: take.isObie)
        _reminderDate = State(initialValue: take.timeReminder?.scheduledDate ?? Self.defaultReminderDate)
        _reminderAlarm = State(initialValue: take.timeReminder?.alarmEnabled ?? true)
        _reminderAllDay = State(initialValue: take.timeReminder?.isAllDay ?? false)
        _reminderRecurrence = State(initialValue: take.timeReminder?.recurrence ?? .none)
        _reminderWeekdays = State(initialValue: take.timeReminder?.weekdays ?? [])
        _reminderLocation = State(initialValue: take.locationReminder)
        _phase = State(initialValue: .opening(start: .now))
    }

    // MARK: - Petals

    private enum PetalKind: Int, CaseIterable {
        case note, task, remind, obie
        /// Final screen-frame angle in degrees (y down; −90 = straight up).
        var finalAngle: Double {
            switch self {
            case .note:   return -80
            case .task:   return -80 + 160.0 / 3
            case .remind: return -80 + 320.0 / 3
            case .obie:   return 80
            }
        }
        /// When this petal leaves the rising deck (seconds from open start).
        var peel: Double {
            switch self {
            case .note:   return Choreo.rise   // rides the deck to the top
            case .task:   return 0.250
            case .remind: return 0.185
            case .obie:   return 0.120
            }
        }
        var sweep: Double { finalAngle - Choreo.riseAngle }
        var sweepDuration: Double { max(0.28, sweep * 0.0055) }   // ~5.5ms/°
        var title: String {
            switch self {
            case .note: return "Note"
            case .task: return "Task"
            case .remind: return "Remind"
            case .obie: return "Obie"
            }
        }
        var systemImage: String? {
            switch self {
            case .note:   return "note.text"
            case .task:   return "checkmark.square"
            case .remind: return "bell"
            case .obie:   return nil   // ObieGlyph (brand mark)
            }
        }
        /// Stable suffix for the XCUITest accessibilityIdentifier ("dial-petal-task" etc.).
        var identifierSuffix: String {
            switch self {
            case .note: return "note"
            case .task: return "task"
            case .remind: return "remind"
            case .obie: return "obie"
            }
        }
        /// ON-state fill = the SAME colour the Iris uses for this type, matching the
        /// Sequence filter toggles (owner 2026-06-29). Obie uses the Iris's Obie-ring
        /// gold (Glow Night / Ember Daylight); Note/Task/Remind use their quadrant fills.
        func activeFill(_ scheme: ColorScheme) -> Color {
            switch self {
            case .note:   return Quadrant.note(scheme)
            case .task:   return Quadrant.task(scheme)
            case .remind: return Quadrant.reminder(scheme)
            case .obie:   return Quadrant.obieRing(scheme)
            }
        }
    }

    // MARK: - Choreography (constants from the approved HiFi v1.6 §10 mode B)

    private enum Choreo {
        static let riseAngle: Double = -90
        static let radius: CGFloat = 68     // owner 2026-06-15: 56 → 68, scaled with the 44pt hub/Marks
        static let startRadius: CGFloat = 8
        static let rise: Double = 0.340          // phase-1 emergence
        static let radialBlend: Double = 0.520   // spiral: radius reaches R over this
        static let irisTurn: Double = 0.700      // hub rotation incl. ±6° overshoot
        static let closeSpeed: Double = 1.25     // exit plays the mirror this much faster
        static var total: Double {               // open end (last petal settles)
            PetalKind.allCases.map { $0.peel + $0.sweepDuration }.max() ?? 1
        }
    }

    // Easings — identical curves to the prototype.
    private static func easeOutBack(_ p: Double) -> Double {
        let s = 1.15
        return 1 + (s + 1) * pow(p - 1, 3) + s * pow(p - 1, 2)
    }
    private static func easeOutCubic(_ p: Double) -> Double { 1 - pow(1 - p, 3) }
    private static func easeInCubic(_ p: Double) -> Double { p * p * p }
    private static func easeInOutCubic(_ p: Double) -> Double {
        p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }

    private struct PetalState {
        var angle: Double
        var radius: CGFloat
        var opacity: Double
    }

    /// Pure open-kinematics for a petal at time t. The close evaluates this at
    /// mirrored time (TOTAL − t·closeSpeed) — a strict reverse incl. the
    /// outward kick from the reversed overshoot.
    private static func openState(_ kind: PetalKind, at t: Double) -> PetalState {
        if t < kind.peel {
            // Riding the deck — rising straight up out of the Iris.
            let g = easeInOutCubic(min(max(t / Choreo.rise, 0), 1))
            return PetalState(
                angle: Choreo.riseAngle,
                radius: Choreo.startRadius + (Choreo.radius - Choreo.startRadius) * g,
                opacity: min(t / 0.08, 1)
            )
        }
        // Peeled off — sweeping clockwise while the radius blends out (spiral).
        let q = min((t - kind.peel) / kind.sweepDuration, 1)
        let rPeel = Choreo.startRadius + (Choreo.radius - Choreo.startRadius)
            * easeInOutCubic(min(kind.peel / Choreo.rise, 1))
        let rq = min((t - kind.peel) / min(Choreo.radialBlend, kind.sweepDuration), 1)
        return PetalState(
            angle: Choreo.riseAngle + kind.sweep * easeOutBack(q),
            radius: rPeel + (Choreo.radius - rPeel) * easeOutCubic(rq),
            opacity: 1
        )
    }

    private func petalState(_ kind: PetalKind, now: Date) -> PetalState {
        switch phase {
        case .opening(let start):
            let t = now.timeIntervalSince(start)
            return Self.openState(kind, at: t)
        case .open:
            return PetalState(angle: kind.finalAngle, radius: Choreo.radius, opacity: 1)
        case .closing(let start, _):
            let tm = Choreo.total - now.timeIntervalSince(start) * Choreo.closeSpeed
            if tm <= 0 { return PetalState(angle: Choreo.riseAngle, radius: Choreo.startRadius, opacity: 0) }
            return Self.openState(kind, at: tm)
        case .dismissed:
            return PetalState(angle: Choreo.riseAngle, radius: Choreo.startRadius, opacity: 0)
        }
    }

    /// Open-time hub rotation with the petals' soft-catch character: ~6° past the
    /// mark, then settle — nothing moves precisely between two points. Factored out
    /// so the CLOSE can evaluate it at the mirrored time (below), making the hub a
    /// strict time-reverse of the open IN STEP with the petals (owner 2026-06-16:
    /// the close used to drive the hub on its OWN faster clock, so the Iris finished
    /// its turn well before the Marks had spiralled back into it).
    private static func openHubRotation(at t: Double) -> Double {
        func turn(_ p: Double, from a: Double, over b: Double, to c: Double) -> Double {
            // two-segment keyframe: a → b (72%, ease-out) → c (settle)
            if p < 0.72 { return a + (b - a) * easeOutCubic(p / 0.72) }
            return b + (c - b) * easeInOutCubic((p - 0.72) / 0.28)
        }
        let tt = t - PetalKind.obie.peel   // the hub starts turning at the first peel
        guard tt > 0 else { return 0 }
        return turn(min(tt / Choreo.irisTurn, 1), from: 0, over: 96, to: 90)
    }

    private func hubRotation(now: Date) -> Double {
        switch phase {
        case .opening(let start):
            return Self.openHubRotation(at: now.timeIntervalSince(start))
        case .open:
            return 90
        case .closing(let start, _):
            // Same mirrored clock the petals use (petalState .closing) — a strict
            // reverse of the open, so hub and Marks land together.
            let tm = Choreo.total - now.timeIntervalSince(start) * Choreo.closeSpeed
            if tm <= 0 { return 0 }
            return Self.openHubRotation(at: tm)
        case .dismissed:
            return 0
        }
    }

    /// Only the live phases drive the TimelineView; `.open` and `.dismissed` are
    /// static so it pauses (and `.dismissed` lets the overlay be removed).
    private var isAnimating: Bool {
        switch phase {
        case .opening, .closing: return true
        case .open, .dismissed:  return false
        }
    }

    /// The veil commits-and-closes only while the ring is OPEN. See the `.allowsHitTesting`
    /// note on the veil — gating this prevents a lingering veil from eating taps.
    private var veilIsInteractive: Bool {
        if case .open = phase { return true }
        return false
    }

    /// The dim veil's opacity, ramped on the fan's OWN clock so the veil dissolves
    /// symmetrically — fade IN over the open, fade OUT over the close, both at the
    /// same `dur` (owner 2026-06-17: the close felt right and the open should match
    /// its slower pace; previously the open leaned on the 0.2s `fanFade` transition
    /// while the close ramped over ~0.84s). The lit focus card rides the same value.
    /// `.open` holds solid; Reduce Motion (phase jumps straight to `.open`) keeps the
    /// overlay's plain transition.
    private func veilOpacity(now: Date) -> Double {
        let dur = Choreo.total / Choreo.closeSpeed
        switch phase {
        case .opening(let start):
            let p = min(max(now.timeIntervalSince(start) / dur, 0), 1)
            return Self.easeInOutCubic(p)
        case .open:
            return 1
        case .closing(let start, _):
            let p = min(max(now.timeIntervalSince(start) / dur, 0), 1)
            return 1 - Self.easeInOutCubic(p)
        case .dismissed:
            return 0
        }
    }

    // MARK: - Focus card geometry
    //
    // Reconstructs the tapped row's card frame from `hubCentre` (the Iris centre in
    // overlay/window space) using the same layout constants DailiesView lays the row
    // out with, so the lit copy lands exactly over the real (now-dimmed) card.

    /// Card leading edge: the Iris centre is `cardSpineInset` right of it (the Iris
    /// nests into the card's top-left corner, on the spine).
    private var focusCardLeading: CGFloat { hubCentre.x - CatchlightLayout.cardSpineInset }
    /// Card top edge: the Iris straddles it, so its centre sits exactly there.
    private var focusCardTop: CGFloat { hubCentre.y }
    /// Card width: from the leading edge out to the row's 20pt trailing margin.
    private var focusCardWidth: CGFloat { containerWidth - 20 - focusCardLeading }

    // MARK: - Body

    var body: some View {
        ZStack {
            fanContent
            // The reminder "when" editor rides INSIDE the fan's own hierarchy, NOT a
            // system `.sheet`. Presenting a sheet from within this Focus-ring overlay
            // (itself a conditionally-rendered `.overlay` in RootView) left the ring
            // wedged after the picker dismissed — the veil's commit tap went dead and
            // the ring could not be closed, stranding the user (owner-reported lockup,
            // 2026-06-18). A modal presented from inside such an overlay isn't reliably
            // torn down by UIKit, so its gesture/first-responder state never restores.
            // An in-hierarchy layer sidesteps that entirely.
            if showingReminderPicker {
                reminderPickerLayer
                    // Slide UP from the bottom like a system sheet (owner 2026-06-18:
                    // "I like the sheet's motion"). Purely the layer's transition — the
                    // robustness fix (veil hit-testing + `.dismissed` teardown) is
                    // independent, so the sheet-like motion costs no stability.
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }
        }
        // A smooth, minimal-bounce spring approximating the iOS sheet present/dismiss.
        // Slowed to feel more deliberate in BOTH directions (owner 2026-06-18).
        .animation(.spring(response: 0.52, dampingFraction: 0.9), value: showingReminderPicker)
        .onAppear {
            if reduceMotion { phase = .open }
            else { phase = .opening(start: .now) }
            // Settle into the static .open phase once the choreography ends so
            // the TimelineView stops ticking.
            DispatchQueue.main.asyncAfter(deadline: .now() + Choreo.total + 0.05) {
                if case .opening = phase { phase = .open }
            }
        }
    }

    /// The reminder "when" editor, drawn as an opaque layer over the fan (see `body`
    /// for why it is NOT a system sheet). Save/Cancel hide it by clearing
    /// `showingReminderPicker`; `ReminderPickerSheet`'s own `dismiss()` is an inert
    /// no-op in this in-place context, so these closures own the hide.
    private var reminderPickerLayer: some View {
        ReminderPickerSheet(
            initialDate: reminderDate,
            initialAlarm: reminderAlarm,
            initialAllDay: reminderAllDay,
            initialRecurrence: reminderRecurrence,
            initialWeekdays: reminderWeekdays,
            initialLocation: reminderLocation,
            onSave: { date, alarm, allDay, recurrence, weekdays, location in
                reminderDate = date
                reminderAlarm = alarm
                reminderAllDay = allDay
                reminderRecurrence = recurrence
                reminderWeekdays = weekdays
                reminderLocation = location
                hasReminder = true
                showingReminderPicker = false
            },
            onCancel: {
                // Cancel = remove the JUST-ADDED reminder (the picker only opens on
                // an inactive→active petal tap, so there's no pre-existing state to
                // preserve). Clear the place too (2026-07-01) — leaving it made the
                // cancelled selection silently re-commit as a location reminder.
                hasReminder = false
                reminderLocation = nil
                showingReminderPicker = false
            }
        )
        // Background now lives inside ReminderPickerSheet itself (owner 2026-06-29).
    }

    private var fanContent: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isAnimating)) { context in
            let now = context.date
            ZStack {
                // The veil — tap to COMMIT the current selection and dismiss.
                // (Petal taps toggle but never close; the veil tap is the
                // commit gesture — see the 4.5/7.4 audit note in history.)
                Color.ckDim
                    .opacity(veilOpacity(now: now))
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { retractAndDismiss(commit: true) }
                    // The veil only catches taps while the ring is genuinely OPEN.
                    // Once it's opening/closing/dismissed, taps fall THROUGH to the
                    // editor beneath — so a veil that lingers mid-teardown can never
                    // strand the user (owner lockup 2026-06-18).
                    .allowsHitTesting(veilIsInteractive)
                    .accessibilityIdentifier("dial-dim")
                    .accessibilityLabel("Save and close")
                    .accessibilityHint("Double-tap to apply your selection and close.")
                    .accessibilityAddTraits(.isButton)

                // The tapped Take, lifted LIT above the veil (owner 2026-06-16). The
                // veil dims everything; this restores the one Take the fan acts on so
                // it stays clearly readable while its Iris (the hub below) and the
                // Focus-ring sit on top. A pure-visual copy of the real row's card —
                // non-interactive, so a tap here falls through to the veil (commit &
                // close), exactly like tapping any other dimmed area. Positioned from
                // `hubCentre`: the Iris centre sits on the card's top edge and is
                // `cardSpineInset` right of the card's leading edge, and the card runs
                // to the 20pt trailing margin — the same geometry DailiesView lays the
                // row out with. Drawn BEFORE the petals so they still pass above it.
                if showsFocusCard, focusCardWidth > 0 {
                    TakeCardSurface(take: take)
                        .frame(width: focusCardWidth, alignment: .leading)
                        .offset(x: focusCardLeading, y: focusCardTop)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        // Fades out with the veil on close (owner 2026-06-17) so the
                        // lit Take resolves back into the brightening timeline rather
                        // than blinking off when the overlay is removed.
                        .opacity(veilOpacity(now: now))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                ZStack {
                    ForEach(PetalKind.allCases.reversed(), id: \.rawValue) { kind in
                        // Reversed so Notes stacks on top during the emergence.
                        let s = petalState(kind, now: now)
                        let rad = s.angle * .pi / 180
                        petal(kind)
                            .offset(x: cos(rad) * s.radius, y: sin(rad) * s.radius)
                            .opacity(s.opacity)
                    }

                    // Hub — the Iris itself, rotating in place. A vertical
                    // marker line rides the rotation and lands horizontal at
                    // open (UX §6).
                    ZStack {
                        TakeCircleView(take: workingTake, diameter: 44)   // match the timeline Iris (owner 2026-06-15)
                        Capsule()
                            .fill(Color.ckEmber.opacity(0.6))
                            .frame(width: 1.5, height: 17)   // scaled with the 36→44 hub
                            .opacity(hubRotation(now: now) / 90 * 0.9)
                    }
                    .rotationEffect(.degrees(hubRotation(now: now)))
                    .accessibilityLabel("Selected: \(TakeCircleView.activityDescription(for: workingTake))")
                }
                .position(hubCentre)
                .accessibilityElement(children: .contain)
            }
        }
    }

    /// A synthetic Take reflecting the working selection, so the hub circle
    /// previews the result live.
    private var workingTake: Take {
        var t = take
        t.isNote = isNote
        t.setTask(isTask)
        t.isObie = isObie
        // Either/or (owner 2026-06-24): a location reminder takes precedence and clears the
        // time; otherwise the time "when" applies (when present).
        if let reminderLocation {
            t.locationReminder = reminderLocation
            t.timeReminder = nil
        } else {
            t.locationReminder = nil
            t.timeReminder = hasReminder
                ? TimeReminder(scheduledDate: reminderDate,
                               notificationIdentifier: t.id.uuidString,
                               alarmEnabled: reminderAlarm,
                               isAllDay: reminderAllDay,
                               recurrence: reminderRecurrence,
                               weekdays: reminderRecurrence == .weekly ? reminderWeekdays : [])
                : nil
        }
        return t
    }

    private func isActive(_ kind: PetalKind) -> Bool {
        switch kind {
        case .note: return isNote
        case .obie: return isObie
        // A "where" reads as an active Remind exactly like a "when" (2026-07-01,
        // place/time parity — previously a place-reminder Take showed an inactive
        // Remind petal, contradicting the card's place subtext).
        case .remind: return hasReminder || reminderLocation != nil
        case .task: return isTask
        }
    }

    @ViewBuilder
    private func petal(_ kind: PetalKind) -> some View {
        let active = isActive(kind)
        Button {
            toggle(kind)
        } label: {
            ZStack {
                // Dock-button language: background face + Ember@35% ring;
                // active reverses (Ember fill + background glyph), exactly
                // like the filter toggles.
                // Explicit `.zIndex` pins fill < ring < glyph: toggling `active`
                // recolours the fill AND the ring together, and without a pinned
                // order SwiftUI could momentarily paint the fresh fill over the ring
                // (the same repaint reshuffle fixed in TakeRowView — D-044,
                // [[catchlight-take-colour-system]]).
                Circle().fill(active ? kind.activeFill(scheme) : Color.ckBackground)
                    .zIndex(0)
                Circle().strokeBorder(
                    // ON: ring = the per-type fill colour, so the active Mark is a
                    // solid filled circle (fill edge IS the border) exactly like the
                    // Sequence toggles — no separate rim.
                    // OFF: ckAccent @ 0.55, matching the dock / editor bar / search
                    // (owner 2026-06-29; was ckEmber @ 0.35 — too faint, and ckEmber
                    // stayed the low-contrast #C9A96E in Daylight where ckAccent
                    // resolves to the WCAG-safe #856539).
                    active ? kind.activeFill(scheme) : Color.ckAccent.opacity(0.55),
                    lineWidth: 1.5
                )
                .zIndex(1)
                Group {
                    if let symbol = kind.systemImage {
                        Image(systemName: symbol)
                            .font(.system(size: 22, weight: .light))   // dense glyph → 22 (owner 2026-06-29, glyph-size pass; matches the dock toggles)
                            // Off glyph = ckAccent, matching the dock/editor/search off icons.
                            .foregroundStyle(active ? Color.ckBackground : Color.ckAccent)
                    } else {
                        ObieGlyph(size: 22)   // the Obie brand glyph. 26→22 (owner 2026-07-01): the SOLID brand "O" reads heavier than the old ring+dot did, so it matched the control/lock size better at 22 (== the sibling glyphs' base)
                            .foregroundStyle(active ? Color.ckBackground : Color.ckTextObie)
                    }
                }
                .zIndex(2)
            }
            .frame(width: 44, height: 44)
            .frame(minWidth: CatchlightLayout.minTouchTarget,
                   minHeight: CatchlightLayout.minTouchTarget)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dial-petal-\(kind.identifierSuffix)")
        .accessibilityLabel(kind.title)
        .accessibilityValue(isActive(kind) ? "active" : "inactive")
        .accessibilityHint("Double-tap to \(isActive(kind) ? "remove" : "add") \(kind.title).")
        .accessibilityAddTraits(isActive(kind) ? [.isSelected, .isButton] : [.isButton])
    }

    // MARK: - Toggle (Note is the floor)

    private func toggle(_ kind: PetalKind) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            switch kind {
            case .note:   isNote.toggle()
            case .task:   isTask.toggle()
            case .remind:
                // Either/or means "active" can be a "when" OR a "where" — toggling
                // OFF must clear BOTH (2026-07-01: previously only `hasReminder`
                // flipped, so the petal could never remove a place reminder).
                if isActive(.remind) {
                    hasReminder = false
                    reminderLocation = nil
                } else {
                    hasReminder = true
                }
            case .obie:   isObie.toggle()
            }
            // Note is the floor: if nothing else is active, Note re-asserts.
            if !isTask && !isActive(.remind) && !isObie { isNote = true }
        }
        // Turning the Reminder Mark ON pops the date/time picker so the user sets
        // the time (or place) there and then (owner 2026-06-17). Turning it off
        // just clears it.
        if kind == .remind && hasReminder { showingReminderPicker = true }
    }

    // MARK: - Retract

    private func retractAndDismiss(commit: Bool = false) {
        guard case .open = phase else {
            // Mid-choreography taps wait for the settle (matches the prototype guard).
            return
        }
        if reduceMotion {
            finish(commit: commit)
            return
        }
        phase = .closing(start: .now, commit: commit)
        let closeDuration = (Choreo.total / Choreo.closeSpeed) + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + closeDuration) {
            if case .closing(_, let c) = phase { finish(commit: c) }
        }
    }

    private func finish(commit: Bool) {
        // Go STATIC before removing the overlay so the TimelineView pauses and SwiftUI
        // can actually tear the fan down — a still-animating subtree lingered as a
        // tap-eating ghost veil (owner lockup 2026-06-18). `.dismissed` matches the
        // close animation's end frame, so there's no flash.
        phase = .dismissed
        if commit {
            onCommit(isNote, isTask, hasReminder, hasReminder ? reminderDate : nil, reminderAlarm, reminderAllDay, reminderRecurrence, reminderRecurrence == .weekly ? reminderWeekdays : [], reminderLocation, isObie)
        } else {
            onDismiss()
        }
    }
}

/// The Reminder "when" editor — model C (owner 2026-06-18). A "when" is a scheduled
/// date with two selectable properties: whether it ALSO rings (`alarm`) and whether
/// it's a date-only placement (`allDay`). Popped by the Focus-ring's Reminder Mark
/// (set the "when" at creation) and reusable to change it later. The caller owns what
/// Save/Cancel mean for its own state (the Focus ring uses Cancel to REMOVE a
/// just-added reminder).
///
/// LAYOUT (owner 2026-06-18): quick presets → options (all-day + alarm) → calendar.
/// The actionable controls sit ABOVE the bulky calendar so they're always visible;
/// the calendar — self-evidently a calendar — is what scrolls partially off-screen,
/// never the toggles. All dates come from `Calendar`/style-based formatters, so the
/// picker follows the user's Region (DD/MM vs MM/DD) and 12/24-hour preference.
struct ReminderPickerSheet: View {
    let initialDate: Date
    let onSave: (_ date: Date, _ alarm: Bool, _ allDay: Bool, _ recurrence: TimeReminder.Recurrence, _ weekdays: Set<Int>, _ location: LocationTrigger?) -> Void
    /// Optional — the Focus-ring uses Cancel to REMOVE a just-added reminder; the
    /// editor leaves it nil (Cancel keeps the existing time untouched).
    var onCancel: () -> Void = {}

    @State private var date: Date
    @State private var alarm: Bool
    @State private var allDay: Bool
    @State private var recurrence: TimeReminder.Recurrence
    /// The weekdays a WEEKLY reminder fires on (owner 2026-06-23) — only surfaced/edited
    /// while the cadence is Weekly; cleared otherwise. See `weekdaySection`.
    @State private var weekdays: Set<Int>
    /// The last Quick-set preset chosen, shown in that selector (owner 2026-06-23). Nil
    /// reads as "Select"; picking one jumps `date` to the preset's instant.
    @State private var quickSet: Preset?
    /// The location ("where") for this reminder (owner 2026-06-23) — nil for a time-only
    /// reminder. Edited inline by `LocationEditor` in the Place tab.
    @State private var location: LocationTrigger?
    /// A reminder is EITHER time-based OR location-based (owner 2026-06-24) — the switch
    /// at the top picks which. Seeded to Place when the Take already has a location.
    @State private var mode: ReminderMode
    @Environment(\.dismiss) private var dismiss

    enum ReminderMode: String, CaseIterable, Identifiable {
        case time = "Time", place = "Place"
        var id: String { rawValue }
    }

    init(initialDate: Date,
         initialAlarm: Bool = true,
         initialAllDay: Bool = false,
         initialRecurrence: TimeReminder.Recurrence = .none,
         initialWeekdays: Set<Int> = [],
         initialLocation: LocationTrigger? = nil,
         onSave: @escaping (Date, Bool, Bool, TimeReminder.Recurrence, Set<Int>, LocationTrigger?) -> Void,
         onCancel: @escaping () -> Void = {}) {
        self.initialDate = initialDate
        self.onSave = onSave
        self.onCancel = onCancel
        _date = State(initialValue: initialDate)
        _alarm = State(initialValue: initialAlarm)
        _allDay = State(initialValue: initialAllDay)
        _recurrence = State(initialValue: initialRecurrence)
        _weekdays = State(initialValue: initialWeekdays)
        _location = State(initialValue: initialLocation)
        _mode = State(initialValue: initialLocation != nil ? .place : .time)
    }

    /// Quick "when" presets — one tap fills the calendar below. All computed from
    /// `Calendar.current` (no hardcoded formats), evening at 20:00, the rest at the
    /// scheduler's all-day fire hour so an alarm lands at a sensible time of day.
    private enum Preset: String, CaseIterable, Identifiable {
        case thisEvening = "This evening"
        case tomorrow    = "Tomorrow"
        case thisWeekend = "This weekend"
        case nextWeek    = "Next week"
        var id: String { rawValue }

        func date(now: Date, calendar: Calendar) -> Date {
            let morning = ReminderScheduler.allDayFireHour
            switch self {
            case .thisEvening:
                // 20:00 today, or tomorrow evening if it's already past.
                let today8 = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
                return today8 > now ? today8
                    : (calendar.date(byAdding: .day, value: 1, to: today8) ?? today8)
            case .tomorrow:
                let next = calendar.date(byAdding: .day, value: 1, to: now) ?? now
                return calendar.date(bySettingHour: morning, minute: 0, second: 0, of: next) ?? next
            case .thisWeekend:
                // "THIS weekend" includes the one the user is in (2026-07-01):
                // strictly-after matching on a Saturday/Sunday skipped to NEXT
                // Saturday. On a weekend day, use today (at the morning hour if
                // still ahead, else fall through to the strict next Saturday).
                let weekday = calendar.component(.weekday, from: now)
                if weekday == 7 || weekday == 1 {
                    let today = calendar.date(bySettingHour: morning, minute: 0, second: 0, of: now) ?? now
                    if today > now { return today }
                }
                let sat = Self.nextWeekday(7, after: now, calendar: calendar)   // Saturday
                return calendar.date(bySettingHour: morning, minute: 0, second: 0, of: sat) ?? sat
            case .nextWeek:
                let mon = Self.nextWeekday(2, after: now, calendar: calendar)   // Monday
                return calendar.date(bySettingHour: morning, minute: 0, second: 0, of: mon) ?? mon
            }
        }

        /// The next occurrence of `weekday` (1 = Sunday … 7 = Saturday) strictly after
        /// `date`, ignoring the time of day.
        private static func nextWeekday(_ weekday: Int, after date: Date, calendar: Calendar) -> Date {
            var comps = DateComponents()
            comps.weekday = weekday
            return calendar.nextDate(after: date, matching: comps,
                                     matchingPolicy: .nextTime) ?? date
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    modeSwitch                  // Time | Place — either/or
                    if mode == .time {
                        quickSetSection         // 1 — jump the date to a preset
                        timeSection             // 2 — time of day (hidden when all-day)
                        optionsSection          // 3·4·5 — All-day · Notify · Repeat ▸ Interval
                        calendarSection         // 6 — the date
                    } else {
                        LocationEditor(trigger: $location)
                    }
                }
                .padding()
            }
            // Single-sourced here (owner 2026-06-29) so EVERY presentation path —
            // the in-place editor layer AND the Dailies `.sheet` — gets the app's
            // Ink/Paper background instead of the default system sheet colour.
            .background(Color.ckBackground.ignoresSafeArea())
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Either/or: Place mode saves the location (time cleared downstream); Time
                    // mode saves the time and passes nil location (clearing any prior place).
                    // Weekdays only travel with a WEEKLY cadence — empty otherwise.
                    Button("Done") {
                        onSave(date, alarm, allDay, recurrence,
                               recurrence == .weekly ? weekdays : [],
                               mode == .place ? location : nil)
                        dismiss()
                    }
                    .disabled(mode == .place && location == nil)   // no place chosen yet
                }
            }
        }
        // Open at full height so the controls + as much calendar as fits are visible.
        .presentationDetents([.large])
    }

    // MARK: - Sections

    /// Quick-set, now a Menu selector mirroring the Interval row (owner 2026-06-23):
    /// "Select" by default; choosing a preset jumps `date` to its instant.
    private var quickSetSection: some View {
        Menu {
            Picker("Quick set", selection: $quickSet) {
                ForEach(Preset.allCases) { preset in
                    Text(preset.rawValue).tag(Optional(preset))
                }
            }
        } label: {
            // Shared selector look + 44pt height, matching the Settings pickers
            // (owner 2026-06-29). The card supplies horizontal inset + fill only —
            // SelectorRow owns the height, so it lands at the standard 44pt.
            SelectorRow(icon: "wand.and.stars", label: "Quick set",
                        value: quickSet?.rawValue ?? "Select")
                .padding(.horizontal, 14)
                .background(Color.ckSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .tint(Color.ckEmber)
        .accessibilityIdentifier("reminder-quickset")
        .onChange(of: quickSet) { _, preset in
            if let preset { date = preset.date(now: Date(), calendar: .current) }
        }
        // A hand-edited date invalidates the preset LABEL (2026-07-01): the row
        // otherwise kept reading e.g. "Tomorrow" against a date picked weeks out.
        // Guarded so the preset's own date-jump above doesn't immediately clear it.
        .onChange(of: date) { _, newDate in
            if let preset = quickSet,
               newDate != preset.date(now: Date(), calendar: .current) {
                quickSet = nil
            }
        }
    }

    /// Time of day, split out of the calendar into its own row (owner 2026-06-23). Hidden
    /// for an all-day "when" — a date-only placement has no meaningful time.
    @ViewBuilder
    private var timeSection: some View {
        if !allDay {
            DatePicker(selection: $date, displayedComponents: [.hourAndMinute]) {
                Label("Time", systemImage: "clock")
                    .foregroundStyle(Color.ckTextPrimary)
            }
            .accessibilityIdentifier("reminder-time")
            .cardSurface()
        }
    }

    /// The Time | Place switch (owner 2026-06-24): a reminder is either time-based or
    /// location-based, never both. Switching to Time on save clears any place; switching to
    /// Place clears the time — enforced at the commit ("location wins when present").
    private var modeSwitch: some View {
        Picker("Reminder type", selection: $mode) {
            ForEach(ReminderMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .tint(Color.ckEmber)
        .accessibilityIdentifier("reminder-mode")
    }


    private var optionsSection: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $allDay) {
                Label("All-day", systemImage: "calendar")
            }
            .accessibilityIdentifier("reminder-allday-toggle")
            .padding(.vertical, 6)

            Divider()

            Toggle(isOn: $alarm) {
                // "Notify" (owner 2026-06-21) — more accurate than "Alarm" to what the
                // toggle does (fire a local notification). The model field stays
                // `alarmEnabled`; only the user-facing label changes.
                Label("Notify", systemImage: alarm ? "bell.fill" : "bell.slash")
            }
            .accessibilityIdentifier("reminder-alarm-toggle")
            .padding(.vertical, 6)

            Divider()

            // Repeat (owner 2026-06-21): a toggle that REVEALS the cadence chooser when
            // on, mirroring the All-day / Notify row rhythm. Off = a one-shot (`.none`);
            // turning it on defaults to Daily and the revealed menu refines it. The
            // anchor date below supplies the cadence's time-of-day / weekday / day.
            Toggle(isOn: Binding(
                get: { recurrence != .none },
                set: { on in
                    if on {
                        recurrence = (recurrence == .none ? .daily : recurrence)
                    } else {
                        recurrence = .none
                        weekdays = []   // drop any day set so it can't linger for the next cadence
                    }
                }
            )) {
                Label("Repeat", systemImage: "repeat")
            }
            .accessibilityIdentifier("reminder-repeat-toggle")
            .padding(.vertical, 6)

            if recurrence != .none {
                Divider()
                Menu {
                    // Weekday presets ("Every weekday"/"Every weekend"/"Custom") are surfaced
                    // as first-class interval choices for discoverability (owner 2026-06-30);
                    // `cadenceBinding` maps them to `.weekly` + a weekday set.
                    Picker("Repeat", selection: cadenceBinding) {
                        ForEach(CadenceChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    MenuFieldRow(title: "Interval", icon: "clock", value: cadenceBinding.wrappedValue.rawValue)
                }
                .accessibilityIdentifier("reminder-repeat-cadence")

                // The day strip appears for the day-set weekly cadences (Every weekday / Every
                // weekend / Custom); plain "Weekly" (same weekday each week) shows no strip.
                if recurrence == .weekly && !weekdays.isEmpty {
                    Divider()
                    weekdaySection
                        .padding(.vertical, 6)
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: recurrence != .none)
        .animation(.snappy(duration: 0.2), value: recurrence == .weekly && !weekdays.isEmpty)
        .tint(Color.ckEmber)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Color.ckSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The seven-day toggle strip for the day-set weekly cadences (owner 2026-06-23; simplified
    /// 2026-06-30 now that Every weekday / Every weekend / Custom are chosen in the Interval
    /// menu). Starts on SUNDAY; each letter maps to a Calendar weekday number (1 = Sun … 7 = Sat).
    /// Shown only when `weekdays` is non-empty (i.e. not plain "Weekly").
    private var weekdaySection: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols          // index 0 = Sunday
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { idx in                        // 0 = Sun … 6 = Sat
                let weekday = idx + 1                                   // Calendar weekday number
                let isOn = weekdays.contains(weekday)
                Button {
                    if isOn { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                } label: {
                    Text(symbols[idx])
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(isOn ? Color.ckEmber.opacity(0.85) : Color.ckBackground, in: Circle())
                        .overlay(Circle().strokeBorder(Color.ckEmber.opacity(0.35), lineWidth: 1))
                        .foregroundStyle(isOn ? Color.ckBackground : Color.ckTextPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reminder-weekday-\(weekday)")
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
    }

    /// The cadence choices shown in the Interval menu (owner 2026-06-30). The weekly family —
    /// Weekly (same weekday each week), Every weekday, Every weekend, Custom — all map to
    /// `.weekly`, differing only by the `weekdays` set; the rest map straight to `Recurrence`.
    private enum CadenceChoice: String, CaseIterable, Identifiable {
        case hourly = "Hourly"
        case daily = "Daily"
        case weekly = "Weekly"
        case everyWeekday = "Every weekday"
        case everyWeekend = "Every weekend"
        case custom = "Custom"
        case monthly = "Monthly"
        case annually = "Annually"
        var id: String { rawValue }
    }

    /// Maps `recurrence` + `weekdays` to/from the Interval selection. Reading derives the
    /// weekly-family label from the day set (empty = Weekly, the two presets, else Custom);
    /// writing sets the cadence AND the day set together, seeding Custom with the reminder's
    /// own weekday so its strip opens non-empty.
    private var cadenceBinding: Binding<CadenceChoice> {
        Binding(
            get: {
                switch recurrence {
                case .hourly:   return .hourly
                case .daily:    return .daily
                case .monthly:  return .monthly
                case .annually: return .annually
                case .none:     return .daily   // not shown — the Repeat toggle owns on/off
                case .weekly:
                    if weekdays.isEmpty { return .weekly }
                    if weekdays == TimeReminder.weekdaySet { return .everyWeekday }
                    if weekdays == TimeReminder.weekendSet { return .everyWeekend }
                    return .custom
                }
            },
            set: { choice in
                switch choice {
                case .hourly:       recurrence = .hourly;   weekdays = []
                case .daily:        recurrence = .daily;    weekdays = []
                case .weekly:       recurrence = .weekly;   weekdays = []
                case .everyWeekday: recurrence = .weekly;   weekdays = TimeReminder.weekdaySet
                case .everyWeekend: recurrence = .weekly;   weekdays = TimeReminder.weekendSet
                case .custom:
                    recurrence = .weekly
                    // Seed a single day (the anchor's weekday) unless a bespoke set already exists.
                    if weekdays.isEmpty || weekdays == TimeReminder.weekdaySet || weekdays == TimeReminder.weekendSet {
                        weekdays = [Calendar.current.component(.weekday, from: date)]
                    }
                case .monthly:      recurrence = .monthly;  weekdays = []
                case .annually:     recurrence = .annually; weekdays = []
                }
            }
        )
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The DATE only — time of day is the separate `timeSection` row above (owner
            // 2026-06-23), so this graphical calendar is purely the day. The Sunday-first
            // calendar in the environment makes the grid start on Sunday to match the
            // weekly day strip (owner 2026-06-23) — display only, the model maths is
            // unaffected.
            DatePicker("When",
                       selection: $date,
                       displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.calendar, Self.weekStartsSunday)
                .tint(Color.ckEmber)
        }
    }

    /// A copy of the user's calendar pinned to a Sunday week-start, for the graphical
    /// calendar + (already) the weekly day strip. Display only — never used for scheduling.
    static let weekStartsSunday: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 1   // Sunday
        return c
    }()

}

/// The shared rounded-surface "card" wrapper for a single picker row (owner 2026-06-23) —
/// the Quick-set and Time rows match the All-day/Notify/Repeat card's padding, fill, and
/// Ember accent so every row in the sheet reads as one family.
private extension View {
    func cardSurface() -> some View {
        self
            .tint(Color.ckEmber)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.ckSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview("Petal fan — Night") {
    GeometryReader { geo in
        PetalFanView(
            take: Take(blocks: [.checkItem("Shape me")]),
            hubCentre: CGPoint(x: 60, y: geo.size.height / 2),
            onCommit: { _, _, _, _, _, _, _, _, _, _ in },
            onDismiss: {}
        )
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.dark)
}

#Preview("Petal fan — Daylight") {
    GeometryReader { geo in
        PetalFanView(
            take: Take(blocks: [.textLine("Shape me")]),
            hubCentre: CGPoint(x: 60, y: geo.size.height / 2),
            onCommit: { _, _, _, _, _, _, _, _, _, _ in },
            onDismiss: {}
        )
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.light)
}
