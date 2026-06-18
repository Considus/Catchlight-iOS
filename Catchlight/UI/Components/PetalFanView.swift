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
    let onCommit: (_ isNote: Bool, _ isTask: Bool, _ hasReminder: Bool, _ reminderDate: Date?, _ reminderAlarm: Bool, _ reminderAllDay: Bool, _ isObie: Bool) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
         onCommit: @escaping (Bool, Bool, Bool, Date?, Bool, Bool, Bool) -> Void,
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
            case .obie:   return nil   // ObiePetalGlyph
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
            onSave: { date, alarm, allDay in
                reminderDate = date
                reminderAlarm = alarm
                reminderAllDay = allDay
                hasReminder = true
                showingReminderPicker = false
            },
            onCancel: {
                hasReminder = false
                showingReminderPicker = false
            }
        )
        .background(Color.ckBackground.ignoresSafeArea())
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
        if hasReminder {
            t.timeReminder = TimeReminder(scheduledDate: reminderDate,
                                          notificationIdentifier: t.id.uuidString,
                                          alarmEnabled: reminderAlarm,
                                          isAllDay: reminderAllDay)
        } else {
            t.timeReminder = nil
        }
        return t
    }

    private func isActive(_ kind: PetalKind) -> Bool {
        switch kind {
        case .note: return isNote
        case .obie: return isObie
        case .remind: return hasReminder
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
                Circle().fill(active ? Color.ckEmber : Color.ckBackground)
                Circle().strokeBorder(
                    active ? Color.ckEmber : Color.ckEmber.opacity(0.35),
                    lineWidth: 1.5
                )
                if let symbol = kind.systemImage {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .light))   // scaled with the 36→44 Mark
                        .foregroundStyle(active ? Color.ckBackground : Color.ckEmber)
                } else {
                    ObiePetalGlyph(size: 20)   // scaled with the 36→44 Mark, keeping the petal's tuned ratio (D-042)
                        .foregroundStyle(active ? Color.ckBackground : Color.ckTextObie)
                }
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
            case .remind: hasReminder.toggle()
            case .obie:   isObie.toggle()
            }
            // Note is the floor: if nothing else is active, Note re-asserts.
            if !isTask && !hasReminder && !isObie { isNote = true }
        }
        // Turning the Reminder Mark ON pops the date/time picker so the user sets
        // the time there and then (owner 2026-06-17). Turning it off just clears it.
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
            onCommit(isNote, isTask, hasReminder, hasReminder ? reminderDate : nil, reminderAlarm, reminderAllDay, isObie)
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
    let onSave: (_ date: Date, _ alarm: Bool, _ allDay: Bool) -> Void
    /// Optional — the Focus-ring uses Cancel to REMOVE a just-added reminder; the
    /// editor leaves it nil (Cancel keeps the existing time untouched).
    var onCancel: () -> Void = {}

    @State private var date: Date
    @State private var alarm: Bool
    @State private var allDay: Bool
    @Environment(\.dismiss) private var dismiss

    init(initialDate: Date,
         initialAlarm: Bool = true,
         initialAllDay: Bool = false,
         onSave: @escaping (Date, Bool, Bool) -> Void,
         onCancel: @escaping () -> Void = {}) {
        self.initialDate = initialDate
        self.onSave = onSave
        self.onCancel = onCancel
        _date = State(initialValue: initialDate)
        _alarm = State(initialValue: initialAlarm)
        _allDay = State(initialValue: initialAllDay)
    }

    /// Quick "when" presets — one tap fills the calendar below. All computed from
    /// `Calendar.current` (no hardcoded formats), evening at 18:00, the rest at the
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
                // 18:00 today, or tomorrow evening if it's already past.
                let today6 = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
                return today6 > now ? today6
                    : (calendar.date(byAdding: .day, value: 1, to: today6) ?? today6)
            case .tomorrow:
                let next = calendar.date(byAdding: .day, value: 1, to: now) ?? now
                return calendar.date(bySettingHour: morning, minute: 0, second: 0, of: next) ?? next
            case .thisWeekend:
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
                    presetsSection
                    optionsSection
                    calendarSection
                }
                .padding()
            }
            .navigationTitle("When")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(date, alarm, allDay); dismiss() }
                }
            }
        }
        // Open at full height so the controls + as much calendar as fits are visible.
        .presentationDetents([.large])
    }

    // MARK: - Sections

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Quick set")
            // Two columns at this width — chips wrap rather than scroll, so all four
            // presets are visible at once.
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Preset.allCases) { preset in
                    Button { date = preset.date(now: Date(), calendar: .current) } label: {
                        Text(preset.rawValue)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.ckSurface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.ckEmber.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.ckTextPrimary)
                    .accessibilityIdentifier("reminder-preset-\(preset.rawValue)")
                }
            }
        }
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
                Label("Alarm", systemImage: alarm ? "bell.fill" : "bell")
            }
            .accessibilityIdentifier("reminder-alarm-toggle")
            .padding(.vertical, 6)
        }
        .tint(Color.ckEmber)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Color.ckSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // All-day collapses the time row: a date-only "when" has no meaningful time.
            DatePicker("When",
                       selection: $date,
                       displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(Color.ckEmber)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2)
            .tracking(0.6)
            .foregroundStyle(Color.ckTextSecondary)
    }
}

#Preview("Petal fan — Night") {
    GeometryReader { geo in
        PetalFanView(
            take: Take(blocks: [.checkItem("Shape me")]),
            hubCentre: CGPoint(x: 60, y: geo.size.height / 2),
            onCommit: { _, _, _, _, _, _, _ in },
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
            onCommit: { _, _, _, _, _, _, _ in },
            onDismiss: {}
        )
    }
    .background(Color.ckBackground)
    .preferredColorScheme(.light)
}
